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
    OUTPUT = /\A(==?)([<>]*)\s*/
    TAG_OUTPUT = /\A\s*(==?)(['<>]*)\s*/
    REDUNDANT_DIV = /\Adiv(?=[.#][\p{Word}-])/
    LOCALS_HEADER = %r{\A﻿?/#\s*locals:}
    CODE_LINE = /\A(?:-|==?[<>]*) (.+)\z/
    # `while x do` is valid Ruby that nobody writes.
    LOOP = /\A(?:while|until|for)\b/
    # Prism 1.x counts in a node's flags whether it starts a line.
    NEWLINE_FLAG = defined?(Prism::NodeFlags::NEWLINE) ? Prism::NodeFlags::NEWLINE : 0
    FIELDS_BY_NODE_CLASS = {}

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
      return content unless code && !code.include?("#") && !code.end_with?("{", "|", ",", "\\", ";", "&&", "||")
      return content if code.match?(Compiler::BLOCK_SELF_OPENING) || code.match?(LOOP)

      "#{content} do"
    end

    def initialize(tailwind_classes: SuperSlim.tailwind_classes, max_line_length: nil, attribute_delimiters: "()")
      @tailwind_classes = tailwind_classes
      @line_wrapper = LineWrapper.new(max_line_length, tailwind_classes:, attribute_delimiters:) if max_line_length
    end

    def call(source)
      formatted = layout(source)
      formatted_ruby = compiled_ruby(formatted) unless formatted == source
      if formatted_ruby && !same_ruby?(compiled_ruby(source), formatted_ruby)
        raise UnsafeFormattingError, "Formatting would change how this template renders"
      end
      return formatted unless @line_wrapper

      wrapped = @line_wrapper.call(formatted)
      return formatted if wrapped == formatted

      wrapped_ruby = compiled_ruby(wrapped)
      # Only Prism's tree vouches for a wrap: a compile error can read the same before and after it.
      return formatted unless wrapped_ruby.is_a?(Prism::ParseResult)

      same_ruby?(formatted_ruby || compiled_ruby(formatted), wrapped_ruby) ? wrapped : formatted
    # Prism walks code recursively too: code nested thousands deep can't be checked, so it isn't formatted.
    rescue SystemStackError
      raise UnsafeFormattingError, "Code nested too deep to check that formatting changes nothing"
    end

    private

    def layout(source)
      parser = Parser.new(outline: true, tailwind_classes: @tailwind_classes)
      parser.call(source)
      lines = source.delete_prefix("﻿").split(/\r?\n/)

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
      lines.each.with_index(1) do |line, lineno|
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
          indent = info.depth * INDENT_WIDTH
          indent_shift = indent_shift_by_lineno[lineno] = indent - indent_of(line)
          content = structure(line, info)
          # Code that goes on over more lines takes its `do` once the line wrapper joins it.
          content = Formatter.with_do(content) if block_opening_linenos.include?(lineno) && !info.text && outline[lineno + 1]&.kind != :continuation
          formatted << (" " * indent) + content
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
      line.sub(/\A[ \t]*/) { _1.gsub(Parser::TAB, "\\1#{" " * Parser::TAB_SIZE}") }
    end

    # Prism's tree of the compiled Ruby; that Ruby with its separators folded when Prism can't read it; the error
    # when the template doesn't compile.
    def compiled_ruby(source)
      nodes = Parser.new(tailwind_classes: @tailwind_classes).call(source)
      code = Compiler.new(format: :xml).call(with_attributes_sorted_by_name(nodes))
      parsed = Prism.parse("#{CodeWrapper::TEMPLATE_METHOD}#{code}\nend")
      parsed.success? ? parsed : code.gsub(/(?:\s*[;\n]\s*)+/, ";")
    rescue Error => exception
      exception.message
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

    # Walks both trees with a stack of its own: deep code or a deep template would exhaust Ruby's.
    def same_node?(node, other_node)
      pairs = [[node, other_node]]
      until pairs.empty?
        value, other_value = pairs.pop
        case value
        when Prism::Node
          return false unless value.instance_of?(other_value.class)
          return false unless same_node_value?(value, other_value)
        when Array
          return false unless other_value.is_a?(Array) && value.size == other_value.size
        else
          return false unless value == other_value

          next
        end
        pairs.concat(children_pairs(value, other_value).reverse)
      end
      true
    end

    def same_node_value?(node, other_node)
      # `__LINE__` holds no value in the tree: removing a blank line above it changes what it renders.
      return node.location.start_line == other_node.location.start_line if node.is_a?(Prism::SourceLineNode)

      field_names, located_names, flagged = node_fields(node)
      return false if flagged && (node.send(:flags) & ~NEWLINE_FLAG) != (other_node.send(:flags) & ~NEWLINE_FLAG)
      # 2026-11: Prism 0.19 (Ruby 3.3) keeps the value of an integer or a float out of its fields.
      return node.value == other_node.value if field_names.empty? && (node.is_a?(Prism::IntegerNode) || node.is_a?(Prism::FloatNode))

      located_names.all? { |name| same_name?(node.public_send(name), other_node.public_send(name)) }
    end

    def children_pairs(value, other_value)
      return value.zip(other_value) if value.is_a?(Array)
      return [] if value.is_a?(Prism::SourceLineNode)

      node_fields(value).first.map { |name| [value.public_send(name), other_value.public_send(name)] }
    end

    # Beside a location, a field holds either a name or, from Prism 2 on, the source the location covers
    # (`opening` beside `opening_loc`): only the name counts.
    def same_name?(name, other_name)
      return true unless name.is_a?(Symbol) || other_name.is_a?(Symbol)

      name == other_name
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
