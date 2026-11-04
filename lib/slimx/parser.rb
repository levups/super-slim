# frozen_string_literal: true

require "strscan"

module SlimX
  # Reads each line with one StringScanner that moves forward: no MatchData, and no copy of the rest of the
  # line after each token, so parsing allocates little more than the nodes it builds.
  class Parser
    include AST

    TAB_SIZE = 4
    TAB = /\G((?: {#{TAB_SIZE}})*) {0,#{TAB_SIZE - 1}}\t/
    DELIMITERS = {"(" => ")", "[" => "]", "{" => "}"}.freeze
    SUPPORTED_ENGINES = %w[javascript css ruby markdown].freeze
    # Engines Slim ships that SlimX deliberately refuses, so they fail loudly instead of parsing as a tag.
    UNSUPPORTED_ENGINES = %w[asciidoc textile rdoc coffee sass scss less erb builder creole wiki org].freeze
    ENGINE = /(#{Regexp.union(SUPPORTED_ENGINES + UNSUPPORTED_ENGINES)})(?:\s*(?:(.*)))?:(\s*)/
    DOCTYPE = /doctype\b/

    ATTRIBUTE_NAME = /\s*([^\0\s"'><\/=()\[\]{}]+)/
    QUOTED_ATTRIBUTE = /#{ATTRIBUTE_NAME}\s*=(=?)\s*("|')/
    CODE_ATTRIBUTE = /#{ATTRIBUTE_NAME}\s*=(=?)\s*/
    SPLAT = /\s*\*(?=[^\s]+)/
    ATTRIBUTE_LIST_OPENING = /\s*([(\[{])/
    BLANK_LINE = /\A\s*\z/
    BLANK_REST = /\s*\z/
    WHITESPACE = /\s*/
    SPACE_BYTE = " ".ord
    TAB_BYTE = "\t".ord
    # At the scanner, the rest of the line is only this character; on a whole line, the line ends with it.
    LINE_CONTINUATION = /[,\\]\z/
    BACKSLASH_AT_END = /\\\z/
    WHITESPACE_MARKERS = /[<>']*/
    TEXT_LINE_INDICATOR = /([|'])([<>]{1,2}(?: |\z)| ?)/
    HTML_COMMENT = /\/!( ?)/
    CONDITIONAL_COMMENT = /\/\[\s*(.*?)\s*\]\s*\z/
    NESTED_TAG = /\s*:\s*/
    TAG_OUTPUT = /\s*=(=?)(['<>]*)/
    CLOSED_TAG = /\s*\/\s*/
    SHORTCUT_VALUE_TO_ESCAPE = /[&<>"']/
    # Runs of characters the scanners would otherwise copy one by one: no delimiter, no line continuation.
    CODE_CHUNK_BY_CLOSING = [nil, *DELIMITERS.values].to_h { [_1, /(?:[^\s(\[{,\\#{Regexp.escape(_1.to_s)}]|[,\\](?!\z))+/] }.freeze
    NESTED_CODE_CHUNK_BY_OPENING = DELIMITERS.to_h { |opening, closing| [opening, /(?:[^,\\#{Regexp.escape(opening + closing)}]|[,\\](?!\z))+/] }.freeze
    QUOTED_CHUNK_BY_QUOTE = %w[" '].to_h { [_1, /(?:[^{}\\#{_1}]|\\(?!\z))+/] }.freeze
    SLASH, PIPE, APOSTROPHE, LESS_THAN, GREATER_THAN, DASH, EQUALS = "/|'<>-=".bytes
    OPENING_BRACE, CLOSING_BRACE = "{}".bytes
    WHITESPACE_MARKER_BYTES = "<>'".bytes.freeze
    BOOLEAN_ATTRIBUTE_BY_CLOSING = DELIMITERS.values.to_h { [_1, /#{ATTRIBUTE_NAME}(?=(\s|#{Regexp.escape(_1)}|\z))/] }.freeze
    ATTRIBUTE_LIST_END_BY_CLOSING = DELIMITERS.values.to_h { [_1, /\s*#{Regexp.escape(_1)}/] }.freeze
    CODE_END_BY_CLOSING = [nil, *DELIMITERS.values].to_h { [_1, /[\s#{Regexp.escape(_1.to_s)}]/] }.freeze

    # What the formatter and the linter need to know about each source line, indexed by line number.
    LineInfo = Struct.new(:kind, :depth, :owner, :text, :output_column)

    attr_reader :outline, :line_by_node

    def initialize(shortcuts: Shortcuts::DEFAULT, file: nil, outline: false, tailwind_classes: SlimX.tailwind_classes)
      @file = file
      @shortcuts = Shortcuts.for(shortcuts, tailwind_classes: !!tailwind_classes)
      @tag = @shortcuts.tag_pattern
      @record_outline = outline
    end

    def call(source)
      root = []
      if @record_outline
        @outline = [nil]
        @line_by_node = {}.compare_by_identity
      end
      source = normalize(source)
      # A string separator splits 6x faster than the regexp, which only templates with \r need.
      @lines = source.include?("\r") ? source.split(/\r?\n/) : source.split("\n")
      @scanner = StringScanner.new("")
      @stacks = [root]
      @indents = []
      @lineno = 0
      parse_line while next_line
      root
    ensure
      @lines = @stacks = @line = @scanner = nil
    end

    private

    def normalize(source)
      source = +source
      unless source.encoding == Encoding::UTF_8
        original_encoding = source.encoding
        source.force_encoding(Encoding::UTF_8)
        source.force_encoding(original_encoding) unless source.valid_encoding?
      end
      source.delete_prefix("﻿")
    end

    def next_line
      if @lines.empty?
        @line = nil
      else
        @line = @lines.shift
        @lineno += 1
        @scanner.string = @line
        @outline << LineInfo.new(:continuation, nil, @structure_lineno) if @outline
        @line
      end
    end

    # Continuation lines are read stripped at both ends.
    def expect_next_line
      next_line || syntax_error!("Unexpected end of file")
      @scanner.string = @line.strip
    end

    def outline_line(kind)
      @outline[@lineno].kind = kind if @outline
    end

    # Characters of the line read so far, even when the scanner reads a stripped copy or attribute source.
    def column
      @line.size - (@scanner.string.size - @scanner.charpos)
    end

    def located(node, lineno = @lineno)
      @line_by_node[node] = lineno if @outline
      node
    end

    # Counts bytes rather than searching for a regexp, which would allocate a MatchData for every line.
    def indent_of(line)
      indent = 0
      indent += 1 while line.getbyte(indent) == SPACE_BYTE
      return indent unless line.getbyte(indent) == TAB_BYTE

      line[/\A[ \t]*/].gsub(TAB, "\\1#{" " * TAB_SIZE}").size
    end

    def parse_line
      if @line.match?(BLANK_LINE)
        outline_line(:blank)
        return @stacks.last << NEWLINE
      end

      indent = indent_of(@line)
      @indents << indent if @indents.empty?
      @scanner.skip(WHITESPACE)
      expecting_indentation = @stacks.size > @indents.size

      if indent > @indents.last
        syntax_error!("Unexpected indentation") unless expecting_indentation
        @indents << indent
      else
        @stacks.pop if expecting_indentation
        while indent < @indents.last && @indents.size > 1
          @indents.pop
          @stacks.pop
        end
        syntax_error!("Malformed indentation") if indent != @indents.last
      end

      if @outline
        @structure_lineno = @lineno
        @outline[@lineno] = LineInfo.new(:structure, @indents.size - 1)
      end
      parse_line_indicators
    end

    def parse_line_indicators
      case @scanner.peek_byte
      when SLASH then parse_comment
      when PIPE, APOSTROPHE then parse_text_line
      when LESS_THAN then parse_inline_html
      when DASH then parse_control
      when EQUALS then parse_output
      else parse_tag_line
      end
      @stacks.last << NEWLINE
    end

    def parse_comment
      if @scanner.skip(HTML_COMMENT)
        text_indent = @indents.last + @scanner[1].size + 2
        @stacks.last << Comment.new(parse_text_block(@scanner.rest, text_indent))
      elsif @scanner.match?(CONDITIONAL_COMMENT)
        syntax_error!("Conditional comments are not supported")
      else
        skip_comment_block
      end
    end

    def parse_text_line
      @scanner.skip(TEXT_LINE_INDICATOR)
      indicator = @scanner[1]
      markers = @scanner[2]
      leading_whitespace = markers.include?("<")
      trailing_whitespace = indicator == "'" || markers.include?(">")
      @stacks.last << Static.new(" ") if leading_whitespace
      lineno = @lineno
      @stacks.last << located(TextBlock.new(parse_text_block(@scanner.rest, @indents.last + markers.count(" ") + 1)), lineno)
      @stacks.last << Static.new(" ") if trailing_whitespace
    end

    def parse_inline_html
      children = []
      @stacks.last << located(InlineHtml.new(@scanner.rest, children))
      @stacks << children
    end

    def parse_control
      lineno = @lineno
      @scanner.pos += 1
      children = []
      @stacks.last << located(Control.new(parse_broken_line, children), lineno)
      @stacks << children
    end

    def parse_output
      position = @scanner.pos + 1
      escape = @line.getbyte(position) != EQUALS
      position += 1 unless escape
      leading_whitespace = trailing_whitespace = false
      while (byte = @line.getbyte(position)) == LESS_THAN || byte == GREATER_THAN
        leading_whitespace ||= byte == LESS_THAN
        trailing_whitespace ||= byte == GREATER_THAN
        position += 1
      end
      @scanner.pos = position
      children = []
      @stacks.last << Static.new(" ") if leading_whitespace
      lineno = @lineno
      @stacks.last << located(Output.new(parse_broken_line, escape, children), lineno)
      @stacks.last << Static.new(" ") if trailing_whitespace
      @stacks << children
    end

    def parse_tag_line
      if @scanner.skip(ENGINE)
        @stacks.last << parse_embedded(@scanner[1], @scanner[2], @scanner.rest)
      elsif @scanner.skip(DOCTYPE)
        @stacks.last << Doctype.new(@scanner.rest.strip)
      elsif (tag = scan_tag)
        parse_tag(tag)
      else
        syntax_error!("Unknown line indicator")
      end
    end

    # A tag name is consumed with its match; a shortcut is left for parse_tag to read as an attribute.
    def scan_tag
      tag = @scanner.check(@tag) or return
      @scanner.pos += tag.bytesize if @scanner[1]
      tag
    end

    def parse_embedded(engine, attributes_source, text)
      syntax_error!("Embedded engine #{engine} is not supported") if UNSUPPORTED_ENGINES.include?(engine)

      lineno = @lineno
      text_indent = @line.size - text.size + attributes_source.size
      @scanner.string = attributes_source
      attributes = parse_attributes
      located Embedded.new(engine, parse_text_block(text, text_indent), attributes), lineno
    end

    def skip_comment_block
      while !@lines.empty? && (@lines.first.match?(BLANK_LINE) || indent_of(@lines.first) > @indents.last)
        next_line
        @stacks.last << NEWLINE
      end
    end

    def parse_text_block(first_line = nil, text_indent = nil)
      nodes = []
      if !first_line || first_line.empty?
        text_indent = nil
      else
        nodes << Text.new(first_line)
        @outline[@lineno].text = true if @outline
      end

      empty_lines = 0
      # Blank lines inside a text block render only when more text follows them.
      rendered_blank_linenos = [] if @outline
      until @lines.empty?
        if @lines.first.match?(BLANK_LINE)
          next_line
          nodes << NEWLINE
          if text_indent
            empty_lines += 1
            rendered_blank_linenos << @lineno if @outline
          else
            outline_line(:blank)
          end
        else
          indent = indent_of(@lines.first)
          break if indent <= @indents.last

          if empty_lines > 0
            nodes << Text.new("\n" * empty_lines)
            empty_lines = 0
          end

          if @outline
            rendered_blank_linenos.each { @outline[_1].kind = :text_blank }
            rendered_blank_linenos.clear
          end
          next_line
          outline_line(:text)

          offset = text_indent ? indent - text_indent : 0
          if offset < 0
            text_indent += offset
            offset = 0
          end
          nodes << NEWLINE << Text.new("#{"\n" if text_indent}#{" " * offset}#{@line.lstrip}")
          text_indent ||= indent
        end
      end
      rendered_blank_linenos.each { @outline[_1].kind = :blank } if @outline
      nodes
    end

    def parse_broken_line
      broken_line = @scanner.rest
      broken_line.strip!
      while broken_line.match?(LINE_CONTINUATION)
        expect_next_line
        broken_line << "\n" << @scanner.string
      end
      broken_line
    end

    def parse_tag(tag)
      tag_lineno = @lineno
      if (shortcut_tag = @shortcuts.tag_by_shortcut[tag])
        @scanner.pos += tag.bytesize unless @shortcuts.attributes_by_shortcut[tag]
        tag = shortcut_tag
      end

      attributes = []
      # Read before it is consumed, so that an illegal shortcut is reported where it starts.
      while (shortcut_length = @scanner.match?(@shortcuts.attribute_pattern))
        shortcut = @scanner[1]
        value = @scanner[2]
        syntax_error!("Illegal shortcut") unless (names = @shortcuts.attributes_by_shortcut[shortcut])

        # Tailwind arbitrary values may hold quotes and ampersands, which Slim names never do.
        value = ERB::Escape.html_escape(value) if value.match?(SHORTCUT_VALUE_TO_ESCAPE)
        names.each { attributes << StaticAttribute.new(_1, value) }
        @shortcuts.additional_attributes_by_shortcut[shortcut]&.each { |name, value| attributes << StaticAttribute.new(name.to_s, value) }
        @scanner.pos += shortcut_length
      end

      leading_whitespace = trailing_whitespace = false
      if WHITESPACE_MARKER_BYTES.include?(@scanner.peek_byte)
        markers = @scanner.scan(WHITESPACE_MARKERS)
        trailing_whitespace = markers.include?(">")
        leading_whitespace = markers.include?("<")
      end

      parse_attributes(attributes)

      siblings = @stacks.last
      content, block, output_whitespace = parse_tag_content
      siblings << Static.new(" ") if leading_whitespace
      siblings << located(Tag.new(tag, attributes, content), tag_lineno)
      siblings << Static.new(" ") if trailing_whitespace
      if output_whitespace
        output_leading_whitespace, output_trailing_whitespace = output_whitespace
        siblings.insert(-2, Static.new(" ")) if output_leading_whitespace && !leading_whitespace
        siblings << Static.new(" ") if output_trailing_whitespace && !trailing_whitespace
      end
      @stacks << block if block
    end

    # Returns the tag content, the block expecting indented children, and the whitespace an `=<>` output adds.
    def parse_tag_content
      output_column = column if @outline
      if @scanner.skip(NESTED_TAG)
        return [[parse_embedded(@scanner[1], @scanner[2], @scanner.rest)]] if @scanner.skip(ENGINE)

        (tag = scan_tag) || syntax_error!("Expected tag")
        content = []
        @stacks << content
        stack_index = @stacks.size - 1
        parse_tag(tag)
        @stacks.delete_at(stack_index)
        [content]
      elsif @scanner.skip(TAG_OUTPUT)
        @outline[@lineno].output_column = output_column if @outline
        escape = @scanner[1] != "="
        markers = @scanner[2]
        output_whitespace = [markers.include?("<"), markers.include?(">")]
        children = []
        lineno = @lineno
        [[located(Output.new(parse_broken_line, escape, children), lineno)], children, output_whitespace]
      elsif @scanner.skip(CLOSED_TAG)
        syntax_error!("Unexpected text after closed tag") unless @scanner.eos?
        [nil]
      elsif @scanner.match?(BLANK_REST)
        content = []
        [content, content]
      else
        @scanner.pos += 1 if @scanner.peek_byte == SPACE_BYTE
        text_indent = column
        [[TextBlock.new(parse_text_block(@scanner.rest, text_indent))]]
      end
    end

    def parse_attributes(attributes = [])
      closing = DELIMITERS[@scanner[1]] if @scanner.skip(ATTRIBUTE_LIST_OPENING)

      loop do
        if @scanner.skip(SPLAT)
          attributes << Splat.new(parse_ruby_code(closing))
        elsif @scanner.skip(QUOTED_ATTRIBUTE)
          name = @scanner[1]
          escape = @scanner[2].empty?
          attributes << QuotedAttribute.new(name, escape, parse_quoted_attribute(@scanner[3]))
        elsif @scanner.skip(CODE_ATTRIBUTE)
          name = @scanner[1]
          escape = @scanner[2].empty?
          code = parse_ruby_code(closing)
          syntax_error!("Invalid empty attribute") if code.empty?
          attributes << CodeAttribute.new(name, escape, code)
        else
          break unless closing

          if @scanner.skip(BOOLEAN_ATTRIBUTE_BY_CLOSING[closing])
            attributes << BooleanAttribute.new(@scanner[1])
          elsif @scanner.skip(ATTRIBUTE_LIST_END_BY_CLOSING[closing])
            break
          else
            @scanner.skip(WHITESPACE)
            syntax_error!("Expected attribute") unless @scanner.eos?
            @stacks.last << NEWLINE
            syntax_error!("Expected closing delimiter #{closing}") if @lines.empty?
            next_line
          end
        end
      end
      attributes
    end

    def parse_ruby_code(outer_closing)
      code = +""
      depth = 0
      opening = closing = nil
      code_end = CODE_END_BY_CLOSING[outer_closing]

      until @scanner.eos? || (depth == 0 && @scanner.match?(code_end))
        if @scanner.match?(LINE_CONTINUATION)
          code << @scanner.getch << "\n"
          expect_next_line
        elsif (chunk = @scanner.scan((depth == 0) ? CODE_CHUNK_BY_CLOSING[outer_closing] : NESTED_CODE_CHUNK_BY_OPENING[opening]))
          code << chunk
        else
          character = @scanner.getch
          if depth > 0
            depth += (character == opening) ? 1 : -1
          else
            depth = 1
            opening = character
            closing = DELIMITERS[opening]
          end
          code << character
        end
      end
      syntax_error!("Expected closing delimiter #{closing}") if depth != 0
      code
    end

    def parse_quoted_attribute(quote)
      value = +""
      depth = 0
      quote_byte = quote.ord

      until depth == 0 && @scanner.peek_byte == quote_byte
        if @scanner.eos? || @scanner.match?(BACKSLASH_AT_END)
          value << (@scanner.eos? ? "\n" : " ")
          @stacks.last << NEWLINE
          expect_next_line
        elsif (chunk = @scanner.scan(QUOTED_CHUNK_BY_QUOTE[quote]))
          value << chunk
        else
          byte = @scanner.peek_byte
          depth += 1 if byte == OPENING_BRACE
          depth -= 1 if byte == CLOSING_BRACE
          value << @scanner.getch
        end
      end

      @scanner.pos += 1
      value
    end

    def syntax_error!(message)
      error = SyntaxError.new(message, @file, @line, @lineno, (@line && @scanner) ? column : 0)
      error.set_backtrace(["#{@file}:#{@lineno}", *caller])
      raise error
    end
  end
end
