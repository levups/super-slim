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
      CLOSING_BRACKET_AT_START = /\A[)\]}]/
      NEW_WITHOUT_PARENTHESES = /\.new [^\s=]/
      CHILD_OUTPUT = /\A==?[<>]* \S.*\z/
      CHILD_TEXT = /\A\| ((?![^\s=]*\s*=)[\p{L}\p{N}&]\S*(?:\s.*\S)?)\z/

      # Templates attach ( and [ to their tag but set { apart, as a Ruby block: 6,097 public templates agree.
      OPENING_BY_ATTRIBUTE_DELIMITERS = {"()" => "(", "[]" => "[", "{}" => " {"}.freeze

      def initialize(max_line_length, tailwind_classes:, attribute_delimiters: "()")
        @opening = OPENING_BY_ATTRIBUTE_DELIMITERS.fetch(attribute_delimiters) do
          raise ArgumentError, "Invalid attribute_delimiters #{attribute_delimiters.inspect}: one of #{OPENING_BY_ATTRIBUTE_DELIMITERS.keys.join(", ")}"
        end

        @max_line_length = max_line_length
        @tailwind_classes = tailwind_classes
        @closing = attribute_delimiters[1]
        @attribute_arranger = AttributeArranger.new(tailwind_classes:)
      end

      def call(source, parser: nil)
        lines = source.split("\n")
        unless parser
          parser = Parser.new(outline: true, tailwind_classes: @tailwind_classes)
          parser.call(source)
        end
        outline = parser.outline
        unformatted_linenos = Parser.unformatted_linenos(lines, outline)
        block_opening_linenos = Formatter.block_opening_linenos(parser)
        single_child_tag_linenos = single_child_tag_linenos(parser)
        wrapped = []
        lineno = 1
        while lineno <= lines.size
          info = outline[lineno]
          last_lineno = structure_last_lineno(outline, lineno)
          structure_lines = lines[(lineno - 1)...last_lineno]
          if unformatted_linenos.include?(lineno)
            wrapped.concat(structure_lines)
          else
            laid_out = layout(structure_lines, info, outline, lineno, block_opening_linenos)
            child_lineno = last_lineno + 1
            if laid_out.size == 1 && single_child_tag_linenos.include?(lineno) && outline[child_lineno]&.kind == :structure &&
                !unformatted_linenos.include?(child_lineno)
              # The child is laid out first: code it spreads over lines may join into one.
              child_last_lineno = structure_last_lineno(outline, child_lineno)
              child_lines = layout(lines[(child_lineno - 1)...child_last_lineno], outline[child_lineno], outline, child_lineno, block_opening_linenos)
              joined = with_child(laid_out.first, child_lines.first, info) if child_lines.size == 1
            end
            if joined
              wrapped << joined
              last_lineno = child_last_lineno
            else
              wrapped.concat(laid_out)
            end
            # A `while` keeps its locals from one turn to the next.
            joined = nil
          end
          lineno = last_lineno + 1
        end
        "#{wrapped.join("\n")}\n"
      end

      private

      def structure_last_lineno(outline, lineno)
        last_lineno = lineno
        last_lineno += 1 while outline[last_lineno + 1]&.owner == lineno && CONTINUATION_KINDS.include?(outline[last_lineno + 1].kind)
        last_lineno
      end

      # Tags whose content is one output or one text block.
      def single_child_tag_linenos(parser)
        parser.line_by_node.filter_map do |node, lineno|
          next unless node.is_a?(AST::Tag) && node.content.is_a?(Array)

          content = node.content.reject { _1 == AST::NEWLINE }
          lineno if content.size == 1 && (content.first.is_a?(AST::Output) ? AST.empty?(content.first.children) : content.first.is_a?(AST::TextBlock))
        end.to_set
      end

      # Text moves only when it starts with a letter, a digit or `&`, and its first word isn't followed by `=`: after a
      # tag, anything else may read as an attribute.
      def with_child(tag_line, child_line, info)
        return if info.output_column || info.text || info.nested_tag_columns

        child = child_line.lstrip
        content = child[CHILD_OUTPUT] || child[CHILD_TEXT, 1]
        joined = "#{tag_line} #{content}" if content
        joined if joined && joined.size <= @max_line_length
      end

      def layout(lines, info, outline, lineno, block_opening_linenos)
        return lines unless info.kind == :structure

        spread = lines.size > 1
        code = joined_code(lines, info) if spread
        line = spread ? code || joined_attributes(lines, info) : lines.first
        return lines unless line

        line = line[/\A */] + Formatter.with_do(line.lstrip) if spread && block_opening_linenos.include?(lineno)

        line, arranged_info = @attribute_arranger.call(line, (info if line == lines.first))
        info = arranged_info || info
        line = with_new_parenthesized(line, info)
        return [line] if line.size <= @max_line_length

        broken = wrap(line, info, children?(outline, lineno))
        kept = lines if spread && (code.nil? || Parser.slim_continuation?(lines))
        return kept || broken if broken == [line]

        # Joined back, brackets lose the spaces inside them (`{ a: 1 }` becomes `{a: 1}`), which may now fit.
        rejoined = joined_code(broken, info)
        return [rejoined] if rejoined && rejoined.size <= @max_line_length

        # A string continued with `\` comes back on one line, longer than the author's.
        return kept if kept && broken.max_by(&:size).size > lines.max_by(&:size).size

        broken
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

      # A tag whose attributes stand one per line inside delimiters, on one line: `p {` `title="A"` `} = text`.
      def joined_attributes(lines, info)
        return unless info.text.nil? && lines.first.lstrip.match?(Shortcuts::TAG_PATTERN) && !code_start(lines.first, info.output_column)
        return unless lines.first.rstrip.match?(Parser::OPENING_BRACKET_AT_LINE_END)
        return unless lines.last.strip.match?(CLOSING_BRACKET_AT_START) && lines[1...-1].none? { _1.strip.empty? }

        lines.first.rstrip + lines[1...-1].map(&:strip).join(" ") + lines.last.strip
      end

      def children?(outline, lineno)
        next_structure = outline[(lineno + 1)..].find { _1.kind == :structure }
        next_structure && next_structure.depth > outline[lineno].depth
      end

      def wrap(line, info, opens_block)
        indent = line[/\A */]
        lists = info.attribute_lists
        head = line[0...lists.first.first].rstrip if lists&.size == 1
        lines, code_start =
          # Attributes spread over lines would not bring back under the limit a tag whose shortcuts alone pass it.
          if head && named_tag?(head.strip) && head.size + @opening.size <= @max_line_length
            wrap_attributes(line, lists.first, indent, info.output_column)
          else
            [[line], code_start(line, info.output_column)]
          end
        return lines unless code_start && lines.last.size > @max_line_length

        last_indent = lines.last[/\A */]
        code_lines = CodeWrapper.call(lines.last[code_start..], last_indent, head: lines.last[0...code_start], opens_block:, max_line_length: @max_line_length)
        return lines unless code_lines

        lines[0...-1] + code_lines
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
