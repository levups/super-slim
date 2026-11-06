# frozen_string_literal: true

module SuperSlim
  class Formatter
    # Gives each line one layout, whatever its author chose: Ruby code spread over several lines is joined back
    # when it fits in max_line_length, and a longer line is broken: a tag's attributes one per line inside
    # attribute_delimiters, then its Ruby code by CodeWrapper.
    class LineWrapper
      CODE_LINE = /\A *(?:-|==?[<>]*) /
      TAG_OUTPUT = /\G\s*==?['<>]*\s*/
      CONTINUATION_KINDS = %i[continuation text text_blank].freeze
      CONTINUED_LINE = /[,\\(\[{]$/
      CLOSING_BRACKET_AT_START = /\A[)\]}]/
      NEW_WITHOUT_PARENTHESES = /\.new [^\s=]/

      # Templates attach ( and [ to their tag but set { apart, as a Ruby block: 6,097 public templates agree.
      OPENING_BY_ATTRIBUTE_DELIMITERS = {"()" => "(", "[]" => "[", "{}" => " {"}.freeze

      def initialize(max_line_length, tailwind_classes:, attribute_delimiters: "()")
        @opening = OPENING_BY_ATTRIBUTE_DELIMITERS.fetch(attribute_delimiters) do
          raise ArgumentError, "Invalid attribute_delimiters #{attribute_delimiters.inspect}: one of #{OPENING_BY_ATTRIBUTE_DELIMITERS.keys.join(", ")}"
        end

        @max_line_length = max_line_length
        @tailwind_classes = tailwind_classes
        @closing = attribute_delimiters[1]
      end

      def call(source)
        lines = source.split("\n")
        return source unless source.match?(CONTINUED_LINE) || source.match?(NEW_WITHOUT_PARENTHESES) || lines.any? { _1.size > @max_line_length }

        parser = Parser.new(outline: true, tailwind_classes: @tailwind_classes)
        parser.call(source)
        outline = parser.outline
        wrapped = []
        lineno = 1
        while lineno <= lines.size
          info = outline[lineno]
          last_lineno = lineno
          last_lineno += 1 while outline[last_lineno + 1]&.owner == lineno && CONTINUATION_KINDS.include?(outline[last_lineno + 1].kind)
          wrapped.concat(layout(lines[(lineno - 1)...last_lineno], info, outline, lineno))
          lineno = last_lineno + 1
        end
        "#{wrapped.join("\n")}\n"
      end

      private

      def layout(lines, info, outline, lineno)
        return lines unless info.kind == :structure

        line = (lines.size > 1) ? joined_code(lines, info) : lines.first
        return lines unless line

        line = with_new_parenthesized(line, info)
        return [line] if line.size <= @max_line_length

        broken = wrap(line, info, children?(outline, lineno))
        return ((lines.size > 1) ? lines : broken) if broken == [line]

        # Joined back, brackets lose the spaces inside them (`{ a: 1 }` becomes `{a: 1}`), which may now fit.
        rejoined = joined_code(broken, info)
        (rejoined && rejoined.size <= @max_line_length) ? [rejoined] : broken
      end

      def with_new_parenthesized(line, info)
        return line unless line.match?(NEW_WITHOUT_PARENTHESES) && (start = code_start(line, info.output_column))

        line[0...start] + CodeWrapper.parenthesize_new(line[start..])
      end

      # The code of a line continued after a comma, a backslash or an opening bracket, on one line; nil when the
      # continuation lines hold anything else, such as attributes or text.
      def joined_code(lines, info)
        return unless info.text.nil? && code_start(lines.first, info.output_column) && lines.drop(1).none? { _1.strip.empty? }

        lines.drop(1).reduce(lines.first.rstrip) do |joined, line|
          piece = line.strip
          joined = joined.delete_suffix("\\").rstrip
          if piece.match?(CLOSING_BRACKET_AT_START)
            joined.delete_suffix(",") + piece
          elsif joined.match?(Parser::OPENING_BRACKET_AT_LINE_END)
            joined + piece
          else
            "#{joined} #{piece}"
          end
        end
      end

      def children?(outline, lineno)
        next_structure = outline[(lineno + 1)..].find { _1.kind == :structure }
        next_structure && next_structure.depth > outline[lineno].depth
      end

      def wrap(line, info, children)
        indent = line[/\A */]
        lists = info.attribute_lists
        lines, code_start =
          if lists&.size == 1 && named_tag?(line[0...lists.first.first].strip)
            wrap_attributes(line, lists.first, indent, info.output_column)
          else
            [[line], code_start(line, info.output_column)]
          end
        return lines unless code_start && lines.last.size > @max_line_length

        last_indent = lines.last[/\A */]
        code_lines = CodeWrapper.call(lines.last[code_start..], last_indent, opens_block: children)
        return lines unless code_lines

        lines[0...-1] + [lines.last[0...code_start] + code_lines.first, *code_lines.drop(1)]
      end

      # A dynamic tag, `*{tag: name}` or `li: *{tag: name}`, has no name for its attribute list to follow.
      def named_tag?(head)
        !head.empty? && !head.end_with?(":")
      end

      # Returns the lines and where the Ruby code of the last one starts, if it outputs some.
      def wrap_attributes(line, (first, last, spans), indent, output_column)
        attribute_indent = indent + (" " * INDENT_WIDTH)
        closing_line = indent + @closing + line[last..]
        lines = [line[0...first].rstrip + @opening, *spans.map { |span_first, span_last| attribute_indent + line[span_first...span_last] }, closing_line]
        [lines, output_column && code_start(closing_line, output_column - last + indent.size + @closing.size)]
      end

      def code_start(line, output_column)
        if output_column
          TAG_OUTPUT.match(line, output_column)&.end(0)
        elsif (match = CODE_LINE.match(line))
          match.end(0)
        end
      end
    end
  end
end
