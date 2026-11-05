# frozen_string_literal: true

require "ripper"

module SuperSlim
  class Formatter
    # Breaks the lines of a formatted template longer than max_line_length: a tag's attributes one per line
    # inside attribute_delimiters, then the arguments of its Ruby code after each comma, as Slim reads a line ending
    # with a comma as continued on the next one. Lines already spread over several lines are left as they are.
    class LineWrapper
      CODE_LINE = /\A *(?:-|==?[<>]*) /
      TAG_OUTPUT = /\G\s*==?['<>]*\s*/
      OPENINGS = %i[on_lparen on_lbracket on_lbrace on_tlambeg on_embexpr_beg].freeze
      CLOSINGS = %i[on_rparen on_rbracket on_rbrace on_embexpr_end].freeze
      CONTINUATION_KINDS = %i[continuation text text_blank].freeze

      ATTRIBUTE_DELIMITERS = %w[() [] {}].freeze

      def initialize(max_line_length, tailwind_classes:, attribute_delimiters: "()")
        unless ATTRIBUTE_DELIMITERS.include?(attribute_delimiters)
          raise ArgumentError, "Invalid attribute_delimiters #{attribute_delimiters.inspect}: one of #{ATTRIBUTE_DELIMITERS.join(", ")}"
        end

        @max_line_length = max_line_length
        @tailwind_classes = tailwind_classes
        @opening, @closing = attribute_delimiters.chars
      end

      def call(source)
        lines = source.split("\n")
        return source if lines.none? { _1.size > @max_line_length }

        parser = Parser.new(outline: true, tailwind_classes: @tailwind_classes)
        parser.call(source)
        wrapped = lines.each.with_index(1).flat_map do |line, lineno|
          info = parser.outline[lineno]
          next [line] unless line.size > @max_line_length && info.kind == :structure && one_line?(parser.outline[lineno + 1], lineno)

          wrap(line, info, children?(parser.outline, lineno))
        end
        "#{wrapped.join("\n")}\n"
      end

      private

      def one_line?(next_info, lineno)
        next_info.nil? || next_info.owner != lineno || !CONTINUATION_KINDS.include?(next_info.kind)
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

        # Arguments go two levels deeper than the line when it opens a block, so they stand apart from its children.
        argument_indent = indent + (" " * (children ? 2 * INDENT_WIDTH : INDENT_WIDTH))
        lines[0...-1] + wrap_arguments(lines.last, code_start, argument_indent)
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

      def wrap_arguments(line, code_start, argument_indent)
        code = line[code_start..]
        offsets = argument_breaks(code)
        return [line] if offsets.empty?

        first = 0
        first_piece, *pieces = [*offsets, code.bytesize].map do |last|
          piece = code.byteslice(first...last).strip
          first = last
          piece
        end
        [line[0...code_start] + first_piece, *pieces.map { argument_indent + _1 }]
      end

      # Byte offsets right after each comma that separates the arguments of the outermost call, up to its block.
      def argument_breaks(code)
        depth = 0
        offsets = []
        Ripper.lex(code).each do |(_, column), type, token|
          case type
          when :on_heredoc_beg then return []
          when :on_kw then break if token == "do"
          when :on_op
            # `a, b = …` assigns several variables: its commas separate no arguments.
            return [] if depth.zero? && token == "=" && !offsets.empty?
          when :on_comma then offsets << column + 1 if depth.zero?
          when *OPENINGS then depth += 1
          when *CLOSINGS then depth -= 1
          end
        end
        offsets
      end
    end
  end
end
