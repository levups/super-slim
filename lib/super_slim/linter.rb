# frozen_string_literal: true

require "yaml"

module SuperSlim
  class Linter
    Offense = Data.define(:path, :lineno, :rule, :message)

    # What the rules ask of a node's ancestors, worked out as the tree is walked: a list of them, copied at each
    # level, made linting quadratic in the depth of the tree.
    Ancestors = Data.define(:last, :control, :located, :inside_svg, :inside_link, :inside_comment) do
      def self.root = new(nil, nil, nil, false, false, false)

      def under(node, line_by_node)
        tag_name = node.name if node.is_a?(AST::Tag)
        Ancestors.new(
          last: node,
          control: node.is_a?(AST::Control) ? node : control,
          located: line_by_node.key?(node) ? node : located,
          inside_svg: inside_svg || tag_name == "svg",
          inside_link: inside_link || tag_name == "a",
          inside_comment: inside_comment || node.is_a?(AST::Comment)
        )
      end
    end

    # The tree is walked once per template: every rule iterates `visits`, each node with its ancestors.
    Document = Data.define(:path, :lines, :nodes, :outline, :line_by_node, :visits, :tag_visits) do
      # Depth first, children before the next sibling, with a stack of its own: a deep template would exhaust Ruby's.
      def self.visits_of(nodes, line_by_node)
        visits = []
        frames = [[nodes || [], 0, Ancestors.root]]
        until frames.empty?
          frame = frames.last
          siblings, index, ancestors = frame
          next frames.pop if index == siblings.size

          frame[1] += 1
          node = siblings[index]
          next if node == AST::NEWLINE

          visits << [node, ancestors]
          children = children_of(node)
          frames << [children, 0, ancestors.under(node, line_by_node)] if children
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
    GLOB_OPTIONS = %w[include exclude].freeze

    def self.load(directory = Dir.pwd)
      new(configuration(directory).fetch("linters", {}), directory)
    end

    def self.configuration(directory = Dir.pwd)
      path = File.join(directory, CONFIG_FILE)
      configuration = File.exist?(path) ? YAML.safe_load_file(path) || {} : {}
      check_configuration(configuration)
      configuration
    end

    # A value of the wrong shape would fail later, inside a rule, with a NoMethodError naming none of this file.
    def self.check_configuration(configuration)
      raise Error, "#{CONFIG_FILE}: expected a mapping of settings" unless configuration.is_a?(Hash)

      %w[linters format fmt].each do |key|
        raise Error, "#{CONFIG_FILE}: `#{key}` must be a mapping" unless configuration.fetch(key, {}).is_a?(Hash)
      end
      configuration.fetch("linters", {}).each do |rule_name, options|
        raise Error, "#{CONFIG_FILE}: `linters: #{rule_name}` must be a mapping of options" unless options.is_a?(Hash)

        GLOB_OPTIONS.each do |key|
          globs = Array(options[key])
          raise Error, "#{CONFIG_FILE}: `#{rule_name}: #{key}` must be a list of globs" unless globs.all?(String)
        end
      end
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
      visits = Document.visits_of(nodes, parser.line_by_node)
      document = Document.new(path:, lines: source.split(/\r?\n/), nodes:, outline: parser.outline, line_by_node: parser.line_by_node,
        visits:, tag_visits: visits.select { |node,| node.is_a?(AST::Tag) })
      relative_path = File.expand_path(path).delete_prefix(@root)
      offenses = @rules.select { _1.applies_to?(relative_path) }.flat_map { _1.offenses(document, source) }
      # sort_by is not stable: the index keeps offenses of one line in rule order.
      offenses.each_with_index.sort_by { |offense, index| [offense.lineno.to_i, index] }.map(&:first)
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
