# frozen_string_literal: true

require_relative "super_slim/version"
require_relative "super_slim/ast"
require_relative "super_slim/shortcuts"
require_relative "super_slim/parser"
require_relative "super_slim/compiler"
require_relative "super_slim/runtime"

module SuperSlim
  autoload :Formatter, "super_slim/formatter"
  autoload :RuboCop, "super_slim/rubocop"

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
    # Shortcuts also read Tailwind class names, such as `.rounded-b-[3px]` or `.lg:hover:underline`. Off by
    # default so that switching from Slim changes no template: Slim renders `.size-2.5` as two classes.
    attr_accessor :tailwind_classes

    def compile(source, file: nil, tailwind_classes: self.tailwind_classes, **compiler_options)
      Compiler.new(**compiler_options).call(Parser.new(file:, tailwind_classes:).call(source))
    end
  end
end

require_relative "super_slim/railtie" if defined?(Rails::Railtie)
