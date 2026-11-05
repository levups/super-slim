# frozen_string_literal: true

require "yaml"

module SuperSlim
  class Linter
    Offense = Data.define(:path, :lineno, :rule, :message)

    # The tree is walked once per template: every rule iterates `visits`, each node with its ancestors.
    Document = Data.define(:path, :lines, :nodes, :outline, :line_by_node, :visits, :tag_visits) do
      def self.visits_of(nodes, ancestors = [], visits = [])
        nodes&.each do |node|
          next if node == AST::NEWLINE

          visits << [node, ancestors]
          children = children_of(node)
          visits_of(children, [*ancestors, node].freeze, visits) if children
        end
        visits
      end

      def partial?
        File.basename(path.to_s).start_with?("_")
      end

      def xml?
        path.to_s.match?(/\.(xml|rss|atom)\.slim\z/)
      end

      def line_of(node)
        line_by_node[node]
      end

      def each_node(&) = visits.each(&)
      def each_tag(&) = tag_visits.each(&)

      def self.children_of(node)
        case node
        when AST::Tag then node.content
        when AST::Control, AST::Output, AST::TextBlock, AST::Comment, AST::InlineHtml, AST::Embedded then node.children
        end
      end
    end

    CONFIG_FILE = ".super-slim.yml"

    def self.load(directory = Dir.pwd)
      new(configuration(directory).fetch("linters", {}), directory)
    end

    def self.configuration(directory = Dir.pwd)
      path = File.join(directory, CONFIG_FILE)
      File.exist?(path) ? YAML.safe_load_file(path) || {} : {}
    end

    # include: and exclude: globs match paths relative to `root`, the directory of .super-slim.yml.
    def initialize(options_by_rule_name = {}, root = Dir.pwd)
      @root = File.join(File.expand_path(root), "")
      @rules = Rules.all.filter_map do |rule_class|
        options = rule_class::DEFAULTS.merge(options_by_rule_name.fetch(rule_class.rule_name, {}).transform_keys(&:to_sym))
        options = with_preset(rule_class.rule_name, options) if options[:preset]
        rule_class.new(options) if options[:enabled]
      end
    end

    def call(path, source)
      parser = Parser.new(file: path, outline: true)
      nodes = parser.call(source)
      visits = Document.visits_of(nodes)
      document = Document.new(path:, lines: source.split(/\r?\n/), nodes:, outline: parser.outline, line_by_node: parser.line_by_node,
        visits:, tag_visits: visits.select { |node,| node.is_a?(AST::Tag) })
      relative_path = File.expand_path(path).delete_prefix(@root)
      offenses = @rules.select { _1.applies_to?(relative_path) }.flat_map { _1.offenses(document, source) }
      # sort_by is not stable: the index keeps offenses of one line in rule order.
      offenses.each_with_index.sort_by { |offense, index| [offense.lineno, index] }.map(&:first)
    rescue SyntaxError => exception
      [Offense.new(path, exception.lineno, "Syntax", exception.error)]
    end

    private

    # The preset's table goes under the rule's own entries, where `~` drops one of the preset.
    def with_preset(rule_name, options)
      preset_options = PRESETS.dig(options[:preset], rule_name)
      unless preset_options
        presets = PRESETS.filter_map { |preset, options_by_rule| preset if options_by_rule.key?(rule_name) }
        raise Error, "#{rule_name}: unknown preset `#{options[:preset]}`, use one of: #{presets.join(", ")}"
      end

      options.merge(preset_options.to_h { |key, entries| [key, entries.merge(Hash(options[key])).compact] })
    end
  end
end

require_relative "linter/presets"
require_relative "linter/rules"
