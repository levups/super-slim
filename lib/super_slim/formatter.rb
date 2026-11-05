# frozen_string_literal: true

module SuperSlim
  # Rewrites a template in its canonical layout. Text blocks shift as a whole, so the whitespace they render is
  # kept; and the formatted template must compile to the same Ruby as the original, or nothing is rewritten.
  class Formatter
    INDENT_WIDTH = 2
    CONTROL = /\A-\s*/
    OUTPUT = /\A(==?)([<>]*)\s*/
    TAG_OUTPUT = /\A\s*(==?)(['<>]*)\s*/
    REDUNDANT_DIV = /\Adiv(?=[.#][\p{Word}-])/

    def self.call(source, **)
      new(**).call(source)
    end

    def initialize(tailwind_classes: SuperSlim.tailwind_classes)
      @tailwind_classes = tailwind_classes
    end

    def call(source)
      formatted = layout(source)
      return formatted if formatted == source || compiled(formatted) == compiled(source)

      raise UnsafeFormattingError, "Formatting would change how this template renders"
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
      return line unless info.output_column

      before = line[0...info.output_column].rstrip
      line[info.output_column..] =~ TAG_OUTPUT
      $'.empty? ? "#{before} #{$1}#{$2}" : "#{before} #{$1}#{$2} #{$'}"
    end

    def indent_of(line)
      expand_tabs(line)[/\A */].size
    end

    def expand_tabs(line)
      line.sub(/\A[ \t]*/) { _1.gsub(Parser::TAB, "\\1#{" " * Parser::TAB_SIZE}") }
    end

    def compiled(source)
      SuperSlim.compile(source, tailwind_classes: @tailwind_classes, format: :xml).gsub(/(?:\s*[;\n]\s*)+/, ";")
    rescue Error => exception
      exception.message
    end
  end
end
