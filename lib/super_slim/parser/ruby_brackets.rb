# frozen_string_literal: true

module SuperSlim
  class Parser
    # Read by hand, a line at a time: Prism would cost every process that renders templates its load time and memory.
    # Misread, all rare after a bracket that ends its line or before a comment that ends the code: heredocs, `?(`,
    # `$'`, a regexp after a method name or a keyword (`when /'/`), `%` glued to a value (`"%d"%[a]`), interpolation
    # in a %-literal and %-literals between other delimiters (`%|a(|`). A comment is only trusted when a second
    # reading, which takes those for literals, finds it too: in doubt, the code stays whole, as Slim leaves it.
    class RubyBrackets
      PLAIN_RUBY = /[^()\[\]{}"'`#%\/]+/
      PLAIN_RUBY_BEFORE_LITERALS = /[^()\[\]{}"'`#%\/?]+/
      QUOTED_TEXT_BY_DELIMITER = %w[" ` /].to_h { |delimiter| [delimiter, /(?:[^\\#{delimiter}#]|\\.|#(?!\{))*/m] }
        .merge("'" => /(?:[^\\']|\\.)*/m).freeze
      PERCENT_LITERAL_OPENING = /[qQwWiIrsx]?([(\[{<])/
      # Other punctuation closes the %-literal it opens: `%w|a b|`.
      SAME_DELIMITER_PERCENT_LITERAL_OPENING = /[qQwWiIrsx]?([^\w\s(\[{<=])/
      CHARACTER_LITERAL = /\\?[^\s]/
      ARGUMENT_START = /[^\s=]/
      UNDERSCORE_BYTE = "_".ord
      COLON_BYTE = ":".ord
      DIGIT_ZERO_BYTE = "0".ord
      DIGIT_NINE_BYTE = "9".ord
      LOWER_A_BYTE = "a".ord
      LOWER_Z_BYTE = "z".ord
      NON_ASCII_BYTE = 0x80
      BYTES_BEFORE_REGEXP = "\n(,[{|&=!~;:?<>+-*%^".bytes.freeze
      LINE_END = /[ \t]*(?:\n|\z)/
      LINE_END_OR_COMMENT = /[ \t]*(?:[#\n]|\z)/

      # `%w[a) b(]` nests only its own kind of bracket.
      PercentLiteral = Struct.new(:opening, :closing, :depth)

      # Where a comment that follows code on its line starts in code, nil when there is none. One alone on a line is
      # left out: a backslash before it carries the code on to that line.
      def self.code_comment_offset(code)
        return unless code.include?("#")

        offset = new(code).trailing_comment_offset or return
        return unless new(code, literals_after_words: true).trailing_comment_offset == offset

        code_before = code.byteslice(0, offset).sub(/[ \t]+\z/, "")
        offset unless code_before.empty? || code_before.end_with?("\n")
      end

      # The byte offset of the comment that ends the code, if one does.
      attr_reader :trailing_comment_offset

      # With `literals_after_words`, what follows a word and a space reads as the first argument of a method called
      # without parentheses, as Ruby reads it unless the word is a local variable: `split /#/`, `when ?#`, `%w|#|`.
      def initialize(code, literals_after_words: false)
        @literals_after_words = literals_after_words
        @plain_ruby = literals_after_words ? PLAIN_RUBY_BEFORE_LITERALS : PLAIN_RUBY
        @scanner = StringScanner.new(code.dup)
        # Whether each bracket still open ends its line.
        @open_brackets = []
        # The strings, regexps and %-literals the scanner is in, innermost last; an integer is an interpolation, the
        # number of open brackets once its `#{` is counted.
        @literals = []
        read
      end

      def <<(line)
        @trailing_comment_offset = nil
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
          next if @scanner.skip(@plain_ruby)

          character = @scanner.getch
          case character
          when "(", "[", "{" then @open_brackets << @scanner.match?(LINE_END_OR_COMMENT)
          when ")", "]", "}"
            @open_brackets.pop
            return @literals.pop if interpolation_depth && @open_brackets.size < interpolation_depth
          when '"', "'", "`" then return @literals << character
          when "/" then return @literals << character if regexp_start?
          when "%" then return open_percent_literal if percent_literal_start?
          when "?" then @scanner.skip(CHARACTER_LITERAL) if literal_start?
          when "#"
            comment_offset = @scanner.pos - 1
            @scanner.skip_until(LINE_END)
            @trailing_comment_offset = comment_offset if @scanner.eos?
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
        return true if offset.negative? || BYTES_BEFORE_REGEXP.include?(code.getbyte(offset))

        @literals_after_words && offset < @scanner.pos - 2 && @scanner.match?(ARGUMENT_START) && word_byte?(code.getbyte(offset))
      end

      def word_byte?(byte)
        byte == UNDERSCORE_BYTE || byte >= NON_ASCII_BYTE || (byte | 0x20).between?(LOWER_A_BYTE, LOWER_Z_BYTE) ||
          byte.between?(DIGIT_ZERO_BYTE, DIGIT_NINE_BYTE)
      end

      # `:%` is a symbol.
      def percent_literal_start?
        @scanner.scan(PERCENT_LITERAL_OPENING) ||
          (literal_start? && @scanner.string.getbyte(@scanner.pos - 2) != COLON_BYTE && @scanner.scan(SAME_DELIMITER_PERCENT_LITERAL_OPENING))
      end

      def literal_start?
        @literals_after_words && regexp_start?
      end

      def open_percent_literal
        opening = @scanner[1]
        @open_brackets << @scanner.match?(LINE_END)
        @literals << PercentLiteral.new(opening, DELIMITERS.fetch(opening) { (opening == "<") ? ">" : opening }, 1)
      end

      def read_percent_literal(literal)
        until @scanner.eos?
          character = @scanner.getch
          if character == "\\"
            @scanner.getch
          elsif character == literal.closing
            literal.depth -= 1
            next unless literal.depth.zero?

            @open_brackets.pop
            return @literals.pop
          elsif character == literal.opening
            literal.depth += 1
          end
        end
      end
    end
  end
end
