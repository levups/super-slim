# frozen_string_literal: true

require "lint_roller"
require "strscan"
require_relative "../super_slim"
require_relative "linter"

module SuperSlim
  # Loaded by RuboCop from `plugins: [super_slim]`: lints the Ruby of each template, offenses at their place in the `.slim` file.
  module RuboCop
    class Plugin < LintRoller::Plugin
      def about
        LintRoller::About.new(name: "super_slim", version: VERSION, homepage: "https://github.com/levups/super-slim",
          description: "Lints the Ruby of Slim templates, read by SuperSlim's parser")
      end

      def supported?(context)
        context.engine == :rubocop
      end

      def rules(_context)
        ::RuboCop::Runner.ruby_extractors.unshift(RubyExtractor)
        LintRoller::Rules.new(type: :path, config_format: :rubocop, value: File.expand_path("../../config/rubocop.yml", __dir__))
      end
    end

    # Hands RuboCop each piece of Ruby with its offset: a piece is a slice of the template, so autocorrection
    # writes back into the template.
    class RubyExtractor
      Fragment = Struct.new(:code, :offset)

      # Slim reads a control line as the head of a block: its keyword and `do` belong to the indented lines.
      LEADING_KEYWORD = /\A(?:begin|case|else|elsif|ensure|if|rescue|unless|until|when|while|for[ \t]+\w+[ \t]+in)\b[ \t]*/
      TRAILING_DO = /(?:\b[ \t]*|[ \t])do[ \t]*(\|[^|]*\|)?[ \t]*(#.*)?\z/
      WHEN = /\A\s*when[ \t]/
      THEN = /[ \t]then(?:[ \t].*)?\z/m
      INTERPOLATION = /#\{((?>[^{}]|(\{(?>[^{}]|\g<1>)*\}))*)\}/
      ESCAPED_INTERPOLATION = /\\#\{/
      UNESCAPED_INTERPOLATION_CODE = /\A\{.*\}\z/m
      TEXT_WITHOUT_INTERPOLATION = /[^#\\]+|./m

      def self.call(processed_source)
        new(processed_source).call if processed_source.path&.end_with?(".slim")
      end

      def initialize(processed_source)
        @processed_source = processed_source
        @source = processed_source.raw_source
      end

      def call
        fragments.filter_map do |fragment|
          next if fragment.code.strip.empty?

          {offset: fragment.offset, processed_source: processed_source_of(fragment.code)}
        end
      end

      private

      def fragments
        parser = Parser.new(file: @processed_source.path, outline: true, tailwind_classes: tailwind_classes?)
        parser.call(@source)
        parser.ruby_ranges.flat_map do |kind, first, last|
          # From the start of its first line, so that the indentation of a `ruby:` block is the same on every line.
          first = (@source.rindex("\n", first - 1) || -1) + 1 if kind == :embedded_ruby
          fragment = Fragment.new(@source[first...last], first)
          case kind
          when :text then interpolations(fragment)
          when :code then without_block_syntax(fragment)
          when :embedded_ruby then [fragment]
          end
        end
      rescue SyntaxError
        []
      end

      def tailwind_classes?
        configuration = Linter.configuration
        configuration.key?("tailwind_classes") ? configuration["tailwind_classes"] : SuperSlim.tailwind_classes
      end

      def interpolations(text)
        scanner = StringScanner.new(text.code)
        fragments = []
        until scanner.eos?
          next if scanner.skip(ESCAPED_INTERPOLATION)

          if scanner.scan(INTERPOLATION)
            code = scanner[1]
            offset = text.offset + scanner.charpos - code.size - 1
            fragments << (code.match?(UNESCAPED_INTERPOLATION_CODE) ? Fragment.new(code[1..-2], offset + 1) : Fragment.new(code, offset))
          else
            scanner.skip(TEXT_WITHOUT_INTERPOLATION)
          end
        end
        fragments
      end

      def without_block_syntax(fragment)
        whens(fragment).map do |clause|
          keyword = clause.code[LEADING_KEYWORD].to_s
          Fragment.new(clause.code[keyword.size..].sub(TRAILING_DO, ""), clause.offset + keyword.size)
        end
      end

      # `when a, b` holds two expressions, which RuboCop reads as an array: each one becomes a fragment.
      def whens(fragment)
        keyword = fragment.code[WHEN] or return [fragment]
        conditions = fragment.code[keyword.size..].sub(THEN, "")
        array = processed_source_of("[#{conditions}]").ast
        return [fragment] unless array&.array_type?

        array.children.map do |condition|
          Fragment.new(condition.source, fragment.offset + keyword.size + condition.source_range.begin_pos - 1)
        end
      end

      def processed_source_of(code)
        processed_source = ::RuboCop::ProcessedSource.new(code, @processed_source.ruby_version, @processed_source.path,
          parser_engine: @processed_source.parser_engine)
        processed_source.config = @processed_source.config
        processed_source.registry = @processed_source.registry
        processed_source
      end
    end
  end
end
