# frozen_string_literal: true

require_relative "slimx/version"
require_relative "slimx/ast"
require_relative "slimx/shortcuts"
require_relative "slimx/parser"
require_relative "slimx/compiler"
require_relative "slimx/runtime"
require_relative "slimx/formatter"

module SlimX
  autoload :RuboCop, "slimx/rubocop"

  class Error < StandardError; end
  class InvalidAttributeNameError < Error; end
  class UnsafeFormattingError < Error; end

  class SyntaxError < Error
    attr_reader :error, :file, :line, :lineno, :column

    def initialize(error, file, line, lineno, column)
      @error = error
      @file = file || "(__TEMPLATE__)"
      @line = line.to_s
      @lineno = lineno
      @column = column
      super(to_s)
    end

    def to_s
      line = @line.lstrip
      column = @column + line.size - @line.size
      <<~MESSAGE
        #{error}
          #{file}, Line #{lineno}, Column #{@column}
            #{line}
            #{" " * column}^
      MESSAGE
    end
  end

  class << self
    # Strict mode refuses any template that is not already in the layout `slimx fmt` writes.
    attr_accessor :strict

    # Shortcuts also read Tailwind class names, such as `.rounded-b-[3px]` or `.lg:hover:underline`. Off by
    # default so that switching from Slim changes no template: Slim renders `.size-2.5` as two classes.
    attr_accessor :tailwind_classes

    def compile(source, file: nil, shortcuts: Shortcuts::DEFAULT, strict: self.strict, tailwind_classes: self.tailwind_classes,
      **compiler_options)
      ensure_formatted!(source, file, shortcuts, tailwind_classes) if strict
      Compiler.new(**compiler_options).call(Parser.new(file:, shortcuts:, tailwind_classes:).call(source))
    end

    private

    def ensure_formatted!(source, file, shortcuts, tailwind_classes)
      formatted = Formatter.new(shortcuts:, tailwind_classes:).layout(source)
      return if formatted == source

      lines = source.split("\n", -1)
      expected_lines = formatted.split("\n", -1)
      index = lines.each_index.find { |line_index| lines[line_index] != expected_lines[line_index] } || lines.size
      raise SyntaxError.new("Not formatted, `slimx fmt` writes: #{expected_lines[index].inspect}", file, lines[index], index + 1, lines[index].to_s[/\A\s*/].size)
    end
  end
end

require_relative "slimx/railtie" if defined?(Rails::Railtie)
