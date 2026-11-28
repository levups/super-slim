# frozen_string_literal: true

module SuperSlim
  class Parser
    # Read by hand, a line at a time: Prism would cost every process that renders templates its load time and memory.
    # Misread, all rare after a bracket that ends its line or before a comment that ends the code: heredocs, `?(`,
    # `$'`, a regexp after a method name or a keyword (`when /'/`), `%` glued to a value (`"%d"%[a]`), interpolation
    # in a %-literal and %-literals between other delimiters (`%|a(|`).
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
      DOT_BYTE = ".".ord
      EQUALS_BYTE = "=".ord
      SIGIL_BYTES = "@$:".bytes.freeze
      VALUE_OPENING_BYTES = "([{,".bytes.freeze
      KEYWORDS_BEFORE_ARGUMENT = %w[when if unless elsif while until and or not return in then].freeze
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
      # left out: a backslash before it carries the code on to that line. A second reading takes a regexp, a %-literal
      # or `?#` after `.split` or `when` for its argument: when only one reading finds a comment, the code stays whole,
      # as Slim leaves it; when both do, the later `#` is the comment, the other one sits in a literal.
      def self.code_comment_offset(code)
        return unless code.include?("#")

        offset = new(code).trailing_comment_offset or return
        return if alone_on_its_line?(code, offset)

        literal_offset = new(code, literals_after_words: true).trailing_comment_offset or return
        (literal_offset > offset) ? literal_offset : offset
      end

      def self.alone_on_its_line?(code, offset)
        code_before = code.byteslice(0, offset).sub(/[ \t]+\z/, "")
        code_before.empty? || code_before.end_with?("\n")
      end
      private_class_method :alone_on_its_line?

      # The byte offset of the comment that ends the code, if one does.
      attr_reader :trailing_comment_offset

      # With `literals_after_words`, what follows a method or a keyword and a space reads as its first argument:
      # `.split /#/`, `when ?#`, `.concat %w|#|`.
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
          when "%" then return open_percent_literal if scan_percent_literal_opening
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
        offset = offset_before_spaces
        offset.negative? || BYTES_BEFORE_REGEXP.include?(@scanner.string.getbyte(offset)) || argument_start?(offset)
      end

      # Where the second reading opens a character literal or a %-literal between other delimiters: first in the code,
      # after an opening bracket, a comma or ` = `, or as an argument. Elsewhere `?` and `%` may follow a value, after
      # a symbol (`:ok? ?"a":"b"`) or a backslash that joins two lines.
      def literal_start?
        return false unless @literals_after_words

        code = @scanner.string
        offset = offset_before_spaces
        offset.negative? || VALUE_OPENING_BYTES.include?(byte = code.getbyte(offset)) ||
          (byte == EQUALS_BYTE && offset.positive? && code.getbyte(offset - 1) == SPACE_BYTE) || argument_start?(offset)
      end

      # The offset of the byte before the character just read and the spaces before it.
      def offset_before_spaces
        code = @scanner.string
        offset = @scanner.pos - 2
        offset -= 1 while offset >= 0 && (code.getbyte(offset) == SPACE_BYTE || code.getbyte(offset) == TAB_BYTE)
        offset
      end

      # After a method called on a receiver (`.split /#/`) or a keyword (`when ?#`), and a space. A bare name may be a
      # local variable, which Ruby divides (`total /2`) or questions (`x ?'a':'b'`).
      def argument_start?(offset)
        return false unless @literals_after_words && offset < @scanner.pos - 2 && @scanner.match?(ARGUMENT_START)

        code = @scanner.string
        word_end = offset
        offset -= 1 while offset >= 0 && word_byte?(code.getbyte(offset))
        return false if offset == word_end || code.getbyte(offset + 1).between?(DIGIT_ZERO_BYTE, DIGIT_NINE_BYTE)
        return KEYWORDS_BEFORE_ARGUMENT.include?(code.byteslice(offset + 1, word_end - offset)) if offset.negative?

        case code.getbyte(offset)
        when DOT_BYTE then offset.zero? || code.getbyte(offset - 1) != DOT_BYTE
        when *SIGIL_BYTES then false
        else KEYWORDS_BEFORE_ARGUMENT.include?(code.byteslice(offset + 1, word_end - offset))
        end
      end

      def word_byte?(byte)
        byte == UNDERSCORE_BYTE || byte >= NON_ASCII_BYTE || (byte | 0x20).between?(LOWER_A_BYTE, LOWER_Z_BYTE) ||
          byte.between?(DIGIT_ZERO_BYTE, DIGIT_NINE_BYTE)
      end

      def scan_percent_literal_opening
        @scanner.scan(PERCENT_LITERAL_OPENING) || (literal_start? && @scanner.scan(SAME_DELIMITER_PERCENT_LITERAL_OPENING))
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
