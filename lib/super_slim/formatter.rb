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
    # Prism 1.x counts in a node's flags whether it starts a line.
    NEWLINE_FLAG = defined?(Prism::NodeFlags::NEWLINE) ? Prism::NodeFlags::NEWLINE : 0
    FIELDS_BY_NODE_CLASS = {}
    COMPARATOR_BY_NODE_CLASS = {}

    def self.call(source, **)
      new(**).call(source)
    end

    def initialize(tailwind_classes: SuperSlim.tailwind_classes, max_line_length: nil, attribute_delimiters: "()")
      @tailwind_classes = tailwind_classes
      @line_wrapper = LineWrapper.new(max_line_length, tailwind_classes:, attribute_delimiters:) if max_line_length
    end

    def call(source)
      parser = Parser.new(outline: true, tailwind_classes: @tailwind_classes)
      nodes = parser.call(source)
      formatted = layout(source, parser.outline)
      layout_changed = formatted != source
      if layout_changed
        formatted_code = compiled_code(formatted)
        raise UnsafeFormattingError, "Formatting would change how this template renders" unless same_code?(compiled_code(source, nodes), formatted_code)
      end
      return formatted unless @line_wrapper

      wrapped = @line_wrapper.call(formatted, outline: (parser.outline unless layout_changed))
      return formatted if wrapped == formatted

      wrapped_ruby = parsed_ruby(compiled_code(wrapped))
      # Only Prism's tree vouches for a wrap: a compile error can read the same before and after it.
      return formatted unless wrapped_ruby.is_a?(Prism::ParseResult)

      formatted_code = compiled_code(source, nodes) unless layout_changed
      same_ruby?(parsed_ruby(formatted_code), wrapped_ruby) ? wrapped : formatted
    # Prism walks code recursively too: code nested thousands deep can't be checked, so it isn't formatted.
    rescue SystemStackError
      raise UnsafeFormattingError, "Code nested too deep to check that formatting changes nothing"
    end

    private

    def layout(source, outline)
      source = source.delete_prefix("﻿")
      lines = Parser.split_lines(source)

      formatted = []
      indent_shift_by_lineno = {}
      lines.each.with_index(1) do |line, lineno|
        info = outline[lineno]
        case info.kind
        when :blank
          formatted << "" unless formatted.empty? || formatted.last.empty?
        when :text_blank
          formatted << ""
        when :structure
          indent = info.depth * INDENT_WIDTH
          indent_shift_by_lineno[lineno] = indent - indent_of(line)
          formatted << (" " * indent) + structure(line, info)
        else
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

    # The Ruby the template compiles to, its attributes sorted by name; the error when it doesn't compile.
    def compiled_code(template, nodes = nil)
      nodes ||= Parser.new(tailwind_classes: @tailwind_classes).call(template)
      Compiler.new(format: :xml).call(with_attributes_sorted_by_name(nodes))
    rescue Error => exception
      exception
    end

    # Most templates the layout changes compile to the very same Ruby: only the others are parsed.
    def same_code?(code, other_code)
      (code.is_a?(String) && code == other_code) || same_ruby?(parsed_ruby(code), parsed_ruby(other_code))
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
          return false unless value.instance_of?(other_value.class) && node_comparator(value).call(value, other_value, pending_values)
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

    def node_comparator(node)
      COMPARATOR_BY_NODE_CLASS[node.class] ||= Formatter.comparator_for(node.class, *node_fields(node))
    end

    class << self
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
          eval(<<~LAMBDA, binding, __FILE__, __LINE__ + 1) # rubocop:disable Security/Eval
            ->(value, other_value, pending_values) do
              #{"return false unless #{clauses.join(" && ")}" unless clauses.empty?}
              #{pushes.join("\n")}
              true
            end
          LAMBDA
        end
      end

      private

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
