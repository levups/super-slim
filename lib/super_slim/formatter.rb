# frozen_string_literal: true

require "prism"
require_relative "formatter/attribute_arranger"
require_relative "formatter/code_wrapper"
require_relative "formatter/line_wrapper"

module SuperSlim
  # Rewrites a template in its canonical layout. Text blocks shift as a whole, so the whitespace they render is
  # kept; and the formatted template must compile to the same Ruby as the original, or nothing is rewritten.
  # With max_line_length, longer lines are then wrapped, but only if Prism reads the same Ruby, positions aside.
  class Formatter
    INDENT_WIDTH = 2
    CONTROL = /\A-\s*/
    NEGATED_IF = /\A- if !(?!=)\s*(\S.*)\z/
    COMPOUND_CONDITION = %r{[=<>+*/%&|^~#]|\?\s|\s-\s|:\s|\b(?:and|or|not|then|do)\b}
    ELSE_LINE = /\A\s*-\s*(?:else|elsif)\b/
    OUTPUT = /\A(==?)([<>]*)\s*/
    TAG_OUTPUT = /\A\s*(==?)(['<>]*)\s*/
    REDUNDANT_DIV = /\Adiv(?=[.#][\p{Word}-])/
    LOCALS_HEADER = %r{\A﻿?/#\s*locals:}
    CODE_LINE = /\A(?:-|==?[<>]*) (.+)\z/
    CONTROL_CODE = /\A\s*-\s*(\S.*)/
    # The threshold of the ConsecutiveControlStatements lint rule, plus one.
    RUBY_BLOCK_MIN_LINES = 3
    SKIPPED_KINDS = %i[blank continuation].freeze
    RUBY_BLOCK = /\A\s*ruby:\s*\z/
    CONTROL_RUN = /^( *)- .*\n\1- .*\n\1- /
    # `while x do` is valid Ruby that nobody writes.
    LOOP = /\A(?:while|until|for)\b/
    END_KEYWORD = /\Aend\b/
    # Prism 1.x counts in a node's flags whether it starts a line.
    NEWLINE_FLAG = defined?(Prism::NodeFlags::NEWLINE) ? Prism::NodeFlags::NEWLINE : 0
    FIELDS_BY_NODE_CLASS = {}
    COMPARATOR_BY_NODE_CLASS = {}

    def self.call(source, **)
      new(**).call(source)
    end

    # Slim's own test for a block: children that render something, a comment alone opens none.
    def self.block_opening_linenos(parser)
      parser.line_by_node.filter_map do |node, lineno|
        lineno if (node.is_a?(AST::Output) || node.is_a?(AST::Control)) && !AST.empty?(node.children)
      end.to_set
    end

    # Slim opens a block when Ruby code has children, but only `do` shows that the call takes one. A `#` may start a
    # comment, which `do` would land in.
    def self.with_do(content)
      code = content[CODE_LINE, 1]
      return content if code.nil? || code.include?("#") || code.end_with?("{", "|", ",", "\\", ";", "&&", "||")
      return content if code.match?(Compiler::BLOCK_SELF_OPENING) || code.match?(LOOP)

      "#{content} do"
    end

    def initialize(tailwind_classes: SuperSlim.tailwind_classes, max_line_length: nil, attribute_delimiters: "()")
      @tailwind_classes = tailwind_classes
      @line_wrapper = LineWrapper.new(max_line_length, tailwind_classes:, attribute_delimiters:) if max_line_length
    end

    def call(source)
      parser = Parser.new(outline: true, tailwind_classes: @tailwind_classes)
      nodes = parser.call(source)
      formatted = layout(source, parser)
      unless formatted == source
        source_code = compiled_code(nodes)
        nodes, parser = parsed_template(formatted)
        formatted_code = compiled_code(nodes)
        # Most templates the layout changes compile to the very same Ruby: only the others are parsed.
        unless source_code.is_a?(String) && source_code == formatted_code
          formatted_ruby = parsed_ruby(formatted_code)
          raise UnsafeFormattingError, "Formatting would change how this template renders" unless same_ruby?(parsed_ruby(source_code), formatted_ruby)
        end
      end
      return formatted unless @line_wrapper

      wrapped = @line_wrapper.call(formatted, parser:)
      return formatted if wrapped == formatted

      # `-` code joined by the wrapper may now make a run long enough for a `ruby:` block. A wrap Slim can't read is
      # refused below.
      if wrapped.match?(CONTROL_RUN)
        wrapped_parser = parsed_template(wrapped).last
        wrapped = layout(wrapped, wrapped_parser) if wrapped_parser
      end

      wrapped_ruby = parsed_ruby(compiled_code(parsed_template(wrapped, outline: false).first))
      # Only Prism's tree vouches for a wrap: a compile error can read the same before and after it.
      return formatted unless wrapped_ruby.is_a?(Prism::ParseResult)

      formatted_ruby ||= parsed_ruby(formatted_code || compiled_code(nodes))
      same_ruby?(formatted_ruby, wrapped_ruby) ? wrapped : formatted
    # Prism walks code recursively too: code nested thousands deep can't be checked, so it isn't formatted.
    rescue SystemStackError
      raise UnsafeFormattingError, "Code nested too deep to check that formatting changes nothing"
    end

    private

    def layout(source, parser)
      source = source.delete_prefix("﻿")
      lines = Parser.split_lines(source)

      outline = parser.outline
      unformatted_linenos = Parser.unformatted_linenos(lines, outline)
      first_structure_lineno = (1...outline.size).find { outline[_1].kind == :structure }
      # A partial's signature reads like a method's: alone at the top, set apart from the body.
      locals_header_lineno = first_structure_lineno if first_structure_lineno && lines[first_structure_lineno - 1].match?(LOCALS_HEADER)
      block_opening_linenos = Formatter.block_opening_linenos(parser)
      formatted = []
      indent_shift_by_lineno = {}
      indent_shift = 0
      previous_structure_lineno = nil
      blank_line_pending = false
      # [depth, levels]: the children of a line whose inline tags were spread go that many levels deeper.
      spread_levels = []
      code_lines_by_lineno, rewritten_linenos = ruby_code_layout(lines, outline, parser, unformatted_linenos)
      lines.each.with_index(1) do |line, lineno|
        next if rewritten_linenos.include?(lineno)

        info = outline[lineno]
        # Unformatted lines move with the directive above them, so that they stay inside its block.
        if unformatted_linenos.include?(lineno)
          blank_line_pending = false
          next formatted << shifted(line, indent_shift)
        end

        case info.kind
        when :blank
          formatted << "" unless formatted.empty? || formatted.last.empty?
          blank_line_pending = formatted.last == ""
        when :text_blank
          formatted << ""
          blank_line_pending = false
        when :structure
          previous_info = outline[previous_structure_lineno] if previous_structure_lineno
          # A block's first line comes right after the line that opens it.
          formatted.pop if blank_line_pending && previous_info && info.depth > previous_info.depth
          formatted << "" if previous_structure_lineno && previous_structure_lineno == locals_header_lineno && formatted.last != ""
          spread_levels.pop while spread_levels.last && info.depth <= spread_levels.last[0]
          depth = info.depth + spread_levels.sum { |_depth, levels| levels }
          indent = depth * INDENT_WIDTH
          indent_shift = indent_shift_by_lineno[lineno] = indent - indent_of(line)
          next_info = outline[lineno + 1]
          if (code_lines = code_lines_by_lineno[lineno])
            formatted.concat(code_lines.map { (" " * indent) + _1 })
          elsif info.nested_tag_columns && !(goes_on?(outline, lineno) && next_info.kind != :continuation)
            nested_lines = spread_nested_tags(line, info, depth)
            levels = nested_lines.size - 1
            spread_levels << [info.depth, levels]
            # Attributes going on over the next lines belong to the last tag, and go as many levels deeper.
            indent_shift_by_lineno[lineno] += levels * INDENT_WIDTH
            formatted.concat(nested_lines)
          else
            content = structure(line, info)
            # Code that goes on over more lines takes its `do` once the line wrapper joins it.
            content = Formatter.with_do(content) if block_opening_linenos.include?(lineno) && !info.text && next_info&.kind != :continuation
            content = unless_for_negated_if(content, lines, outline, lineno) if content.start_with?("- if !")
            formatted << (" " * indent) + content
          end
          previous_structure_lineno = lineno
          blank_line_pending = false
        else
          blank_line_pending = false
          formatted << continuation(line, info, indent_shift_by_lineno.fetch(info.owner, 0))
        end
      end
      formatted.pop while formatted.last&.empty?
      formatted.empty? ? "" : "#{formatted.join("\n")}\n"
    end

    # `- if !condition` reads as `- unless condition` when the `!` covers the whole condition and no `else` follows,
    # as RuboCop's Style/NegatedIf asks. A condition holding an operator, a ternary or a keyword keeps its `!`:
    # `!a == b` compares `!a`.
    def unless_for_negated_if(content, lines, outline, lineno)
      condition = content[NEGATED_IF, 1]
      return content if condition.nil? || condition.start_with?("(", "!") || condition.match?(COMPOUND_CONDITION)
      return content if else_follows?(lines, outline, lineno)

      "- unless #{condition}"
    end

    def else_follows?(lines, outline, lineno)
      depth = outline[lineno].depth
      ((lineno + 1)...outline.size).each do |next_lineno|
        info = outline[next_lineno]
        next unless info.kind == :structure && info.depth <= depth
        # A comment between the `if` and its `else` renders nothing.
        next if lines[next_lineno - 1].match?(Parser::CODE_COMMENT)

        return info.depth == depth && lines[next_lineno - 1].match?(ELSE_LINE)
      end
      false
    end

    def structure(line, info)
      content = with_output_spacing(line, info).lstrip
      content = content.rstrip unless info.text
      case content
      when CONTROL then $'.empty? ? "-" : "- #{$'}"
      when OUTPUT then "#{$1}#{$2} #{$'}"
      when REDUNDANT_DIV then $'
      else content
      end
    end

    # One threshold, both ways: `-` lines and `ruby:` blocks next to each other, at one depth, make one run of code
    # lines; three lines or more go in a `ruby:` block, fewer go on `-` lines. Only lines of Ruby complete on their
    # own move, with no block and no comment. Returns the lines that replace each run's first line, and the line
    # numbers they replace.
    def ruby_code_layout(lines, outline, parser, unformatted_linenos)
      # [first line number, last line number, depth, code lines]
      code_units = parser.line_by_node.filter_map do |node, lineno|
        case node
        when AST::Control
          code = control_code(lines[lineno - 1]) if AST.empty?(node.children)
          [lineno, lineno, outline[lineno].depth, [code]] if code && movable_code?(code) && !goes_on?(outline, lineno)
        when AST::Embedded
          next unless node.engine == "ruby" && lines[lineno - 1].match?(RUBY_BLOCK)

          body_linenos = ((lineno + 1)...outline.size).take_while { outline[_1].owner == lineno }
          body = body_linenos.map { lines[_1 - 1].strip }
          [lineno, body_linenos.last, outline[lineno].depth, body] if body.any? && body_linenos.all? { outline[_1].kind == :text } && body.all? { movable_code?(_1) }
        end
      end
      # `format off` keeps its lines as written.
      code_units.reject! { |first_lineno, last_lineno| (first_lineno..last_lineno).any? { unformatted_linenos.include?(_1) } }
      runs = code_units.sort_by!(&:first).chunk_while { |unit, next_unit| next_unit[0] == unit[1] + 1 && next_unit[2] == unit[2] }
      flat_control_linenos = parser.line_by_node.filter_map { |node, lineno| lineno if node.is_a?(AST::Control) && AST.empty?(node.children) }.to_set
      code_lines_by_lineno = {}
      rewritten_linenos = Set.new
      runs.each do |run|
        code_size = run.sum { _1[3].size }
        ruby_blocks = run.count { _1[0] != _1[1] }
        # Already in its layout: a lone `ruby:` block long enough, or `-` lines too few.
        next if (run.size == 1 && ruby_blocks == 1 && code_size >= RUBY_BLOCK_MIN_LINES) || (ruby_blocks.zero? && code_size < RUBY_BLOCK_MIN_LINES)

        # A line Prism can't read alone stays where it is, and splits the run.
        run.chunk { |unit| unit[3].all? { Prism.parse(_1).success? } }.each do |parsable, units|
          code = units.flat_map(&:last)
          ruby_block = code.size >= RUBY_BLOCK_MIN_LINES
          layout_changes = ruby_block || units.any? { _1[0] != _1[1] }
          next unless parsable && layout_changes
          # `-` lines the run can't take, a comment or code going on below, still count for ConsecutiveControlStatements.
          next if !ruby_block && code.size + flat_controls_beside(units, outline, flat_control_linenos) >= RUBY_BLOCK_MIN_LINES

          code_lines_by_lineno[units.first[0]] = ruby_block ? ["ruby:", *code.map { (" " * INDENT_WIDTH) + _1 }] : code.map { "- #{_1}" }
          rewritten_linenos.merge((units.first[0] + 1)..units.last[1])
        end
      end
      [code_lines_by_lineno, rewritten_linenos]
    end

    # The `-` lines with no children right before and after the units, at their depth, blank lines aside: the lint
    # counts them in the same run.
    def flat_controls_beside(units, outline, flat_control_linenos)
      depth = units.first[2]
      [(units.first[0] - 1).downto(1), ((units.last[1] + 1)...outline.size).each].sum do |linenos|
        linenos.lazy
          .reject { SKIPPED_KINDS.include?(outline[_1].kind) }
          .take_while { outline[_1].kind == :structure && outline[_1].depth == depth && flat_control_linenos.include?(_1) }
          .count
      end
    end

    def goes_on?(outline, lineno)
      next_info = outline[lineno + 1]
      next_info&.owner == lineno && next_info.kind != :blank
    end

    def control_code(line)
      line[CONTROL_CODE, 1]&.rstrip
    end

    # A comment would end up after code on a `-` line, which Slim can't read; `#{}` in a string is no comment.
    def movable_code?(code)
      return false if code.match?(Compiler::BLOCK_SELF_OPENING) || code.match?(END_KEYWORD)

      !code.include?("#") || Prism.parse(code).comments.empty?
    end

    # `tr: td = total` nests each tag in the one before: one per line, whatever the line holds. A line whose text goes
    # on over the next ones keeps its inline tags, so that the text stays where it belongs.
    def spread_nested_tags(line, info, depth)
      starts = [0, *info.nested_tag_columns.map(&:last)]
      ends = [*info.nested_tag_columns.map(&:first), line.size]
      starts.zip(ends).each_with_index.map do |(start, finish), level|
        last = level == starts.size - 1
        tag_info = info.dup.tap do |nested_info|
          nested_info.text = nil unless last
          nested_info.output_column = (last && info.output_column) ? info.output_column - start : nil
        end
        (" " * ((depth + level) * INDENT_WIDTH)) + structure(line[start...finish], tag_info)
      end
    end

    def continuation(line, info, indent_shift)
      line = with_output_spacing(expand_tabs(line), info)
      indent = [line[/\A */].size + indent_shift, 0].max
      content = line.lstrip
      content = content.rstrip unless info.kind == :text || info.text
      (" " * indent) + content
    end

    def shifted(line, indent_shift)
      line = expand_tabs(line)
      return "" if line.strip.empty?

      (" " * [line[/\A */].size + indent_shift, 0].max) + line.lstrip
    end

    def with_output_spacing(line, info)
      return line unless info.output_column && line[info.output_column..] =~ TAG_OUTPUT

      before = line[0...info.output_column].rstrip
      $'.empty? ? "#{before} #{$1}#{$2}" : "#{before} #{$1}#{$2} #{$'}"
    end

    def indent_of(line)
      expand_tabs(line)[/\A */].size
    end

    def expand_tabs(line)
      return line unless line.include?("\t")

      line.sub(/\A[ \t]*/) { _1.gsub(Parser::TAB, "\\1#{" " * Parser::TAB_SIZE}") }
    end

    # The template's nodes and its parser, which holds the outline; the error when it doesn't parse.
    def parsed_template(template, outline: true)
      parser = Parser.new(outline:, tailwind_classes: @tailwind_classes)
      [parser.call(template), parser]
    rescue Error => exception
      [exception, nil]
    end

    # The Ruby the nodes compile to, their attributes sorted by name; the error when they don't parse or compile.
    def compiled_code(nodes)
      return nodes if nodes.is_a?(Error)

      Compiler.new(format: :xml).call(with_attributes_sorted_by_name(nodes))
    rescue Error => exception
      exception
    end

    # Prism's tree of the compiled Ruby; that Ruby with its separators folded when Prism can't read it; the error
    # message when the template doesn't compile.
    def parsed_ruby(code)
      return code.message if code.is_a?(Error)

      parsed = Prism.parse("#{CodeWrapper::TEMPLATE_METHOD}#{code}\nend")
      parsed.success? ? parsed : code.gsub(/(?:\s*[;\n]\s*)+/, ";")
    end

    # A tag renders the same whatever the order of its attributes, and with a class shortcut named twice once: both
    # templates get their attributes sorted by name, class values kept in order, before they are compiled. A
    # splat merges attributes in order, so a tag holding one keeps its own.
    def with_attributes_sorted_by_name(nodes)
      nodes.each do |node|
        next unless node.is_a?(Struct)

        if node.is_a?(AST::Tag) && node.attributes.none?(AST::Splat)
          attributes = node.attributes.uniq { class_shortcut?(_1) ? _1 : _1.__id__ }
          node.attributes = attributes.sort_by.with_index { |attribute, index| [attribute.name, index] }
        end
        node.each { with_attributes_sorted_by_name(_1) if _1.is_a?(Array) }
      end
    end

    def class_shortcut?(attribute)
      attribute.is_a?(AST::StaticAttribute) && attribute.name == "class"
    end

    # Positions aside: line breaks, spaces, a trailing comma and the parentheses of a call change nothing, a
    # different value or operator does.
    def same_ruby?(ruby, other_ruby)
      return ruby == other_ruby if ruby.is_a?(String) || other_ruby.is_a?(String)

      same_node?(ruby.value, other_ruby.value) && comment_texts(ruby) == comment_texts(other_ruby)
    end

    # Walks both trees with a stack of its own, the two values of each pair pushed one after the other: deep code or
    # a deep template would exhaust Ruby's.
    def same_node?(node, other_node)
      pending_values = [node, other_node]
      until pending_values.empty?
        other_value = pending_values.pop
        value = pending_values.pop
        case value
        when Prism::Node
          if value.instance_of?(other_value.class)
            return false unless node_comparator(value).call(value, other_value, pending_values)
          else
            pairs = negated_if_pairs(value, other_value) or return false
            pending_values.concat(pairs)
          end
        when Array
          return false unless other_value.is_a?(Array) && value.size == other_value.size

          index = 0
          while index < value.size
            pending_values << value[index] << other_value[index]
            index += 1
          end
        else
          return false unless value == other_value
        end
      end
      true
    end

    # `if !x` and `unless x` with no else run the same code, as RuboCop's Style/NegatedIf holds: the condition and the
    # body still have to match. Only an object that redefines `!` tells them apart. Prism 0.19 names the else
    # branch `consequent`.
    def negated_if_pairs(node, other_node)
      if_node, unless_node = node.is_a?(Prism::IfNode) ? [node, other_node] : [other_node, node]
      return unless if_node.is_a?(Prism::IfNode) && unless_node.is_a?(Prism::UnlessNode)

      negation = if_node.predicate
      return unless negation.is_a?(Prism::CallNode) && negation.name == :! && negation.message == "!" && negation.arguments.nil?
      return if if_node.respond_to?(:subsequent) ? if_node.subsequent : if_node.consequent
      return if unless_node.respond_to?(:else_clause) ? unless_node.else_clause : unless_node.consequent

      [negation.receiver, unless_node.predicate, if_node.statements, unless_node.statements]
    end

    def node_comparator(node)
      COMPARATOR_BY_NODE_CLASS[node.class] ||= Formatter.send(:comparator_for, node.class, *node_fields(node))
    end

    class << self
      private

      # Compares what two nodes of one class hold besides their children, and pushes their children on `pending_values`.
      def comparator_for(node_class, field_names, located_names, flagged)
        if node_class <= Prism::SourceLineNode
          # `__LINE__` holds no value in the tree: removing a blank line above it changes what it renders.
          ->(source_line, other_source_line, _pending_values) { source_line.location.start_line == other_source_line.location.start_line }
        elsif field_names.empty? && (node_class <= Prism::IntegerNode || node_class <= Prism::FloatNode)
          # 2026-11: Prism 0.19 (Ruby 3.3) keeps the value of an integer or a float out of its fields.
          ->(number, other_number, _pending_values) { (!flagged || same_flags?(number, other_number)) && number.value == other_number.value }
        else
          clauses = []
          clauses << "same_flags?(value, other_value)" if flagged
          located_names.each { |name| clauses << "same_name?(value.#{name}, other_value.#{name})" }
          pushes = field_names.map { |name| "pending_values << value.#{name} << other_value.#{name}" }
          # Fields unrolled, without public_send: 2.5x faster with YJIT. The names come from Prism's own classes.
          lambda_from(<<~LAMBDA)
            ->(value, other_value, pending_values) do
              #{"return false unless #{clauses.join(" && ")}" unless clauses.empty?}
              #{pushes.join("\n")}
              true
            end
          LAMBDA
        end
      end

      # Evaluated here, the lambda holds no local but its own source.
      def lambda_from(code)
        eval(code, binding, __FILE__, __LINE__) # rubocop:disable Security/Eval
      end

      def same_flags?(node, other_node)
        (node.send(:flags) & ~NEWLINE_FLAG) == (other_node.send(:flags) & ~NEWLINE_FLAG)
      end

      # Beside a location, a field holds either a name or, from Prism 2 on, the source the location covers
      # (`opening` beside `opening_loc`): only the name counts.
      def same_name?(name, other_name)
        return true unless name.is_a?(Symbol) || other_name.is_a?(Symbol)

        name == other_name
      end
    end

    # 2026-11: Prism 0.19 (Ruby 3.3) has no reflection API: the field names come from the first node of each
    # class. Prism 1.x keeps flags out of deconstruct_keys.
    def node_fields(node)
      FIELDS_BY_NODE_CLASS[node.class] ||= begin
        keys = node.deconstruct_keys(nil).keys
        located_names, field_names = (keys - %i[node_id flags location])
          .reject { _1.end_with?("_loc") }
          .partition { keys.include?(:"#{_1}_loc") }
        [field_names, located_names, node.respond_to?(:flags, true)]
      end
    end

    def comment_texts(ruby)
      ruby.comments.map { |comment| comment.location.slice.strip }
    end
  end
end
