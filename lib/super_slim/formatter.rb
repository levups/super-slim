# frozen_string_literal: true

require "prism"
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

    def self.call(source, **)
      new(**).call(source)
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

      formatted = []
      indent_shift_by_lineno = {}
      lines.each.with_index(1) do |line, lineno|
        info = parser.outline[lineno]
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
      line.sub(/\A[ \t]*/) { _1.gsub(Parser::TAB, "\\1#{" " * Parser::TAB_SIZE}") }
    end

    # Prism's tree of the compiled Ruby; that Ruby with its separators folded when Prism can't read it; the error
    # when the template doesn't compile.
    def compiled_ruby(source)
      code = SuperSlim.compile(source, tailwind_classes: @tailwind_classes, format: :xml)
      parsed = Prism.parse("#{CodeWrapper::TEMPLATE_METHOD}#{code}\nend")
      parsed.success? ? parsed : code.gsub(/(?:\s*[;\n]\s*)+/, ";")
    rescue Error => exception
      exception.message
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
