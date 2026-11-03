# frozen_string_literal: true

require_relative "../slimx"
require_relative "linter"
require_relative "parallel"

module SlimX
  class CLI
    USAGE = <<~TEXT
      Usage: slimx lint [PATH…]             report what breaks the rules of .slimx.yml
             slimx fmt [--check] [PATH…]    rewrite templates in their canonical layout
             slimx version
    TEXT
    SKIPPED_DIRECTORIES = %r{(\A|/)(\.git|node_modules|tmp|vendor)/}
    EX_USAGE = 64

    def call(arguments)
      command, *arguments = arguments
      configuration = Linter.configuration
      SlimX.tailwind_classes = configuration["tailwind_classes"] if configuration.key?("tailwind_classes")
      case command
      when "lint" then lint(arguments, configuration)
      when "fmt" then format(arguments)
      when "version", "--version" then puts(VERSION) || 0
      else warn(USAGE) || EX_USAGE
      end
    end

    private

    def lint(paths, configuration)
      linter = Linter.new(configuration.fetch("linters", {}))
      offenses = Parallel.map(templates(paths)) { linter.call(_1, File.read(_1)) }.flatten
      offenses.each { puts "#{_1.path}:#{_1.lineno}: [#{_1.rule}] #{_1.message}" }
      offenses.empty? ? 0 : 1
    end

    def format(arguments)
      check = arguments.delete("--check")
      outcomes = Parallel.map(templates(arguments)) do |path|
        source = File.read(path)
        formatted = Formatter.call(source)
        next if formatted == source

        File.write(path, formatted) unless check
        [:reformatted, path]
      rescue Error => exception
        [:refused, "#{path}: #{exception.message.lines.first.strip}"]
      end
      outcomes.compact.each { |outcome, text| (outcome == :reformatted) ? puts(text) : warn(text) }
      (outcomes.any? { |outcome,| outcome == :refused || (outcome == :reformatted && check) }) ? 1 : 0
    end

    def templates(paths)
      paths = ["."] if paths.empty?
      paths.flat_map do |path|
        next [path] unless File.directory?(path)

        Dir.glob("**/*.slim", base: path).filter_map { File.join(path, _1) unless _1.match?(SKIPPED_DIRECTORIES) }
      end.sort
    end
  end
end
