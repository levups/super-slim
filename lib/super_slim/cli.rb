# frozen_string_literal: true

require "tempfile"
require_relative "../super_slim"
require_relative "linter"
require_relative "parallel"

module SuperSlim
  class CLI
    USAGE = <<~TEXT
      Usage: super-slim lint [PATH…]               report what breaks the rules of .super-slim.yml
             super-slim format [--check] [PATH…]   rewrite templates in their canonical layout (alias: fmt)
             super-slim version
    TEXT
    SKIPPED_DIRECTORIES = %r{(\A|/)(\.git|node_modules|tmp|vendor)/}
    EX_USAGE = 64
    HELP_OPTIONS = %w[--help -h].freeze
    OPTIONS_BY_COMMAND = {"format" => ["--check"], "fmt" => ["--check"]}.freeze
    # File names and template text reach the terminal and CI logs, where escapes and a `::` line are commands.
    CONTROL_CHARACTER = /[\x00-\x08\x0a-\x1f\x7f]/

    def call(arguments)
      return puts(USAGE) || 0 if arguments.first == "help" || arguments.intersect?(HELP_OPTIONS)

      command, *arguments = arguments
      unknown_option = (arguments.grep(/\A-/) - OPTIONS_BY_COMMAND.fetch(command, [])).first
      return warn("Unknown option #{unknown_option}", USAGE) || EX_USAGE if unknown_option

      configuration = Linter.configuration
      SuperSlim.tailwind_classes = configuration["tailwind_classes"] if configuration.key?("tailwind_classes")
      case command
      when "lint" then lint(arguments, configuration)
      when "format", "fmt" then format(arguments, configuration["format"] || configuration.fetch("fmt", {}))
      when "version", "--version" then puts(VERSION) || 0
      else warn(USAGE) || EX_USAGE
      end
    end

    private

    def lint(paths, configuration)
      begin
        linter = Linter.new(configuration.fetch("linters", {}))
      rescue Error => exception
        return warn(exception.message) || EX_USAGE
      end
      offenses = Parallel.map(templates(paths)) do |path|
        linter.call(path, File.read(path))
      # One template that breaks SuperSlim, a bug or a stack too deep, must not hide the offenses of the others.
      rescue StandardError, SystemStackError => exception
        [Linter::Offense.new(path, 0, "Error", "#{exception.class}: #{exception.message.lines.first&.strip}")]
      end.flatten
      offenses.each { |offense| puts printable("#{offense.path}:#{offense.lineno}: [#{offense.rule}] #{offense.message}") }
      offenses.empty? ? 0 : 1
    end

    def format(arguments, options)
      check = arguments.delete("--check")
      formatter = Formatter.new(max_line_length: options["max_line_length"], attribute_delimiters: options.fetch("attribute_delimiters", "()"))
      outcomes = Parallel.map(templates(arguments)) do |path|
        source = File.read(path)
        formatted = formatter.call(source)
        next if formatted == source

        replace(path, formatted) unless check
        [:reformatted, path]
      rescue StandardError, SystemStackError => exception
        message = exception.message.lines.first&.strip
        [:refused, "#{path}: #{exception.is_a?(Error) ? message : "#{exception.class}: #{message}"}"]
      end
      outcomes.compact.each { |outcome, text| (outcome == :reformatted) ? puts(printable(text)) : warn(printable(text)) }
      (outcomes.any? { |outcome,| outcome == :refused || (outcome == :reformatted && check) }) ? 1 : 0
    end

    # A template found in a directory is a regular file of its own: a symlink in a checkout could point the
    # formatter at any file the user can write, and a device or a FIFO would never end.
    def templates(paths)
      paths = ["."] if paths.empty?
      paths.flat_map do |path|
        next [path] unless File.directory?(path)

        Dir.glob("**/*.slim", base: path).filter_map do |template|
          template_path = File.join(path, template)
          template_path if !template.match?(SKIPPED_DIRECTORIES) && File.lstat(template_path).file?
        end
      end.sort
    end

    # Written beside the template then renamed over it, so that a full disk or a kill cannot leave it cut short.
    def replace(path, content)
      Tempfile.create([".super-slim-", ".tmp"], File.dirname(path)) do |file|
        file.write(content)
        file.close
        File.chmod(File.stat(path).mode & 0o7777, file.path)
        File.rename(file.path, path)
      end
    end

    def printable(text)
      text.gsub(CONTROL_CHARACTER) { |character| character.inspect[1...-1] }
    end
  end
end
