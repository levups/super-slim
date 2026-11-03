# frozen_string_literal: true

# Replays the 70 examples of Slim's literate specification (test/literate/TESTS.md) as a differential test:
# each renders through Slim (HTML5, no sorting) and SlimX, with the options its section declares. The file turns
# on pretty mode only to make its expected HTML readable: both engines render without it.
require "minitest/autorun"
require "slim"
require "slimx/tilt"

class LiterateTest < Minitest::Test
  SPECIFICATION_PATH = File.join(Gem.loaded_specs.fetch("slim").full_gem_path, "test/literate/TESTS.md")
  REFERENCE_OPTIONS = {format: :html, sort_attrs: false, pretty: false}.freeze
  UNSUPPORTED_OPTIONS = %i[disable_escape].freeze
  DROPPED_FEATURES = ["IE conditional comment"].freeze

  Example = Data.define(:title, :slim, :options)

  # Options hold for the rest of their section and its subsections, as in Slim's own runner.
  def self.examples
    examples = []
    options_by_depth = [{}]
    title = []
    lines = File.readlines(SPECIFICATION_PATH, chomp: true)
    until lines.empty?
      line = lines.shift
      if (heading = line.match(/\A(#+)\s*(.*)\z/))
        depth = heading[1].size
        options_by_depth = options_by_depth.first(depth) + [options_by_depth.first(depth).last.dup]
        title = title.first(depth - 1) + [heading[2]]
      elsif (fence = line.match(/\A~{3,}\s*(\w+)\s*\z/))
        block = lines.take_while { !it.match?(/\A~{3,}\s*\z/) }
        lines.shift(block.size + 1)
        case fence[1]
        # The options blocks are Ruby hash literals written by Slim itself, in a gem we installed.
        when "options" then options_by_depth.last.update(eval("{#{block.join("\n")}}", binding, __FILE__, __LINE__)) # rubocop:disable Security/Eval
        when "slim" then examples << Example.new(title.join(" / "), block.join("\n"), options_by_depth.last.dup)
        end
      end
    end
    examples
  end

  examples.each_with_index do |example, index|
    define_method("test_#{index.to_s.rjust(2, "0")}_#{example.title.downcase.gsub(/\W+/, "_")}") { check(example) }
  end

  private

  def check(example)
    unsupported = UNSUPPORTED_OPTIONS.select { example.options[it] }
    skip "Unsupported options #{unsupported.inspect}" if unsupported.any?
    skip "Dropped from SlimX" if DROPPED_FEATURES.any? { example.title.include?(it) }

    assert_equal render_with_slim(example), render_with_slimx(example), "SlimX differs from Slim on:\n#{example.slim}"
  end

  def render_with_slim(example)
    outcome { Slim::Template.new(REFERENCE_OPTIONS.merge(example.options, pretty: false)) { example.slim }.render(Object.new) { "block" } }
  end

  def render_with_slimx(example)
    options = example.options.slice(:format)
    options[:shortcuts] = example.options[:shortcut] if example.options.key?(:shortcut)
    outcome { SlimX::Template.new(options) { example.slim }.render(Object.new) { "block" } }
  end

  def outcome
    yield
  rescue => exception
    "error: #{exception.message.lines.first}"
  end
end
