# frozen_string_literal: true

module SuperSlim
  class Parser
    # A bracket that ends its line and is still open continues the code on the next lines, until it closes. A
    # bracket opened mid-line, as in `items.each { |item|`, doesn't: Slim reads the lines below it as children.
    # Read by hand, a line at a time: Prism would cost every process that renders templates its load time and memory.
    #
    # Misread, as rare after a bracket that ends its line: heredocs, `?(`, `$'`, a regexp after a method name or a
    # keyword (`when /'/`), `%` glued to a value (`"%d"%[a]`), interpolation in a %-literal and %-literals between
    # other delimiters (`%|a(|`).
    class RubyBrackets
      PLAIN_RUBY = /[^()\[\]{}"'`#%\/]+/
      QUOTED_TEXT_BY_DELIMITER = %w[" ` /].to_h { |delimiter| [delimiter, /(?:[^\\#{delimiter}#]|\\.|#(?!\{))*/m] }
        .merge("'" => /(?:[^\\']|\\.)*/m).freeze
      PERCENT_LITERAL_OPENING = /[qQwWiIrsx]?([(\[{<])/
      BYTES_BEFORE_REGEXP = "\n(,[{|&=!~;:?<>+-*%^".bytes.freeze
      LINE_END = /[ \t]*(?:\n|\z)/
      LINE_END_OR_COMMENT = /[ \t]*(?:[#\n]|\z)/

      # `%w[a) b(]` nests only its own kind of bracket.
      PercentLiteral = Struct.new(:opening, :closing, :depth)

      def initialize(code)
        @scanner = StringScanner.new(code.dup)
        # Whether each bracket still open ends its line.
        @open_brackets = []
        # The strings, regexps and %-literals the scanner is in, innermost last; an integer is an interpolation, the
        # number of open brackets once its `#{` is counted.
        @literals = []
        read
      end

      def <<(line)
        @scanner << "\n" << line
        read
        self
      end

      def open_at_line_end?
        @open_brackets.any?
      end

      private

      def read
        until @scanner.eos?
          case (literal = @literals.last)
          when String then read_quoted(literal)
          when PercentLiteral then read_percent_literal(literal)
          else read_code(literal)
          end
        end
      end

      def read_code(interpolation_depth)
        until @scanner.eos?
          next if @scanner.skip(PLAIN_RUBY)

          character = @scanner.getch
          case character
          when "(", "[", "{" then @open_brackets << @scanner.match?(LINE_END_OR_COMMENT)
          when ")", "]", "}"
            @open_brackets.pop
            return @literals.pop if interpolation_depth && @open_brackets.size < interpolation_depth
          when '"', "'", "`" then return @literals << character
          when "/" then return @literals << character if regexp_start?
          when "%" then return open_percent_literal if @scanner.scan(PERCENT_LITERAL_OPENING)
          when "#" then @scanner.skip_until(LINE_END)
          end
        end
      end

      def read_quoted(delimiter)
        until @scanner.eos?
          @scanner.skip(QUOTED_TEXT_BY_DELIMITER[delimiter])
          return @literals.pop if @scanner.skip(delimiter)

          @scanner.getch
          next unless @scanner.skip("{")

          @open_brackets << @scanner.match?(LINE_END_OR_COMMENT)
          return @literals << @open_brackets.size
        end
      end

      def regexp_start?
        code = @scanner.string
        offset = @scanner.pos - 2
        offset -= 1 while offset >= 0 && (code.getbyte(offset) == SPACE_BYTE || code.getbyte(offset) == TAB_BYTE)
        offset.negative? || BYTES_BEFORE_REGEXP.include?(code.getbyte(offset))
      end

      def open_percent_literal
        opening = @scanner[1]
        @open_brackets << @scanner.match?(LINE_END)
        @literals << PercentLiteral.new(opening, DELIMITERS.fetch(opening, ">"), 1)
      end

      def read_percent_literal(literal)
        until @scanner.eos?
          character = @scanner.getch
          if character == "\\"
            @scanner.getch
          elsif character == literal.opening
            literal.depth += 1
          elsif character == literal.closing
            literal.depth -= 1
            next unless literal.depth.zero?

            @open_brackets.pop
            return @literals.pop
          end
        end
      end
    end
  end
end
