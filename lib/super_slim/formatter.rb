# frozen_string_literal: true

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

      same_ruby?(formatted_ruby || compiled_ruby(formatted), compiled_ruby(wrapped)) ? wrapped : formatted
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

    # Prism's tree of the compiled Ruby, or the error that stops it.
    def compiled_ruby(source)
      code = SuperSlim.compile(source, tailwind_classes: @tailwind_classes, format: :xml)
      # Rails runs a template inside a method, where `yield` is valid.
      parsed = Prism.parse("def template\n#{code}\nend")
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

    def same_node?(node, other_node)
      return false unless node.instance_of?(other_node.class)
      # `__LINE__` holds no value in the tree: removing a blank line above it changes what it renders.
      return node.location.start_line == other_node.location.start_line if node.is_a?(Prism::SourceLineNode)

      field_names, flags = node_fields(node)
      return false if flags && (node.send(:flags) & ~NEWLINE_FLAG) != (other_node.send(:flags) & ~NEWLINE_FLAG)

      field_names.all? { |name| same_field?(node.public_send(name), other_node.public_send(name)) }
    end

    def same_field?(value, other_value)
      case value
      when Prism::Node then other_value.is_a?(Prism::Node) && same_node?(value, other_value)
      when Array then other_value.is_a?(Array) && value.size == other_value.size && value.each_index.all? { same_field?(value[_1], other_value[_1]) }
      else value == other_value
      end
    end

    # Prism 0.19 (Ruby 3.3) has no reflection API: the field names come from the first node of each class. Prism
    # 1.x keeps flags out of deconstruct_keys, and counts in them whether a node starts a line.
    def node_fields(node)
      FIELDS_BY_NODE_CLASS[node.class] ||= [
        node.deconstruct_keys(nil).keys.reject { |key| key == :node_id || key == :flags || key == :location || key.end_with?("_loc") },
        node.respond_to?(:flags, true)
      ]
    end

    def comment_texts(ruby)
      ruby.comments.map { |comment| comment.location.slice.strip }
    end
  end
end
