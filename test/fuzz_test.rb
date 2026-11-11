# frozen_string_literal: true

require "minitest/autorun"
require "slim"
require "super_slim/parallel"
require_relative "support/tilt"

# Renders thousands of seeded random templates through Slim and SuperSlim: outputs, or error messages, must match.
class FuzzTest < Minitest::Test
  CASE_COUNT = Integer(ENV.fetch("FUZZ_CASES", 3000))
  SEED = Integer(ENV.fetch("FUZZ_SEED", 20261030))

  class Scope
    def value = %(<b>&"'</b>)
    def safe_number = 42
    def nothing = nil
    def flag = true
    def no_flag = false
    def items = [1, 2]
    def classes = ["a", nil, ["b", ""], :c]
    def attributes_hash = {:title => "<t>", "data-x" => 1, :disabled => true, :hidden => false}
    def data_hash = {user_id: 1, nested: {deep: "<v>"}, flag: true, off: false, none: nil}
    def tag_name = "section"
    def wrap = "[#{yield}]"
  end

  class Generator
    TAGS = %w[div p span a ul li section input br img].freeze
    EXPRESSIONS = %w[value safe_number nothing flag no_flag items.size classes tag_name].freeze

    def initialize(random)
      @random = random
    end

    def template
      lines = []
      lines.concat(block(0)) while lines.size < 6
      lines.join("\n")
    end

    private

    def pick(choices) = choices[@random.rand(choices.size)]
    def chance(probability) = @random.rand < probability

    def block(indent, depth = 0)
      prefix = " " * indent
      case @random.rand(12)
      when 0 then ["#{prefix}| #{text}", *(chance(0.3) ? ["#{prefix}  #{text}"] : [])]
      when 1 then ["#{prefix}#{pick(["=", "==", "=<", "=>", "=<>"])} #{pick(EXPRESSIONS)}"]
      when 2
        ["#{prefix}- if #{pick(%w[flag no_flag nothing])}", *child(indent, depth), "#{prefix}- else", *child(indent, depth)]
      when 3 then ["#{prefix}- items.each do |item|", "#{prefix}  = item", *child(indent, depth)]
      when 4 then ["#{prefix}= wrap do", *child(indent, depth)]
      when 5 then ["#{prefix}/ comment #{text}", "#{prefix}  ignored"]
      when 6 then ["#{prefix}/! html comment #{text}"]
      when 7 then ["#{prefix}<em>#{text}</em>"]
      when 8 then ["#{prefix}#{pick(%w[javascript: css:])}", "#{prefix}  #{text} \#{value}"]
      else tag_block(indent, depth)
      end
    end

    def child(indent, depth)
      (depth < 3) ? block(indent + 2, depth + 1) : ["#{" " * (indent + 2)}| leaf"]
    end

    def tag_block(indent, depth)
      prefix = " " * indent
      head = "#{tag_head}#{attributes}"
      case @random.rand(6)
      when 0 then ["#{prefix}#{head}"]
      when 1 then ["#{prefix}#{head} #{text}"]
      when 2 then ["#{prefix}#{head} #{pick(["=", "==", "=<", "=>"])} #{pick(EXPRESSIONS)}"]
      when 3 then ["#{prefix}#{head}: #{tag_head} #{text}"]
      when 4 then ["#{prefix}#{head}/"]
      else ["#{prefix}#{head}", *child(indent, depth), *(chance(0.5) ? child(indent, depth) : [])]
      end
    end

    def tag_head
      head = case @random.rand(5)
      when 0 then ""
      # Slim reads anything glued to a splat as Ruby code: two stray quotes would pair up across generated code.
      when 1 then return "*{tag: tag_name}"
      else pick(TAGS)
      end
      head = "div" if head.empty? && !chance(0.5)
      head += ".c#{@random.rand(3)}" if chance(0.4) || head.empty?
      head += "#i#{@random.rand(3)}" if chance(0.15)
      head += pick(["<", ">", "<>", "'"]) if chance(0.15)
      head
    end

    def attributes
      return "" if chance(0.4)

      list = Array.new(1 + @random.rand(3)) { attribute }
      if chance(0.5)
        " #{list.join(" ")}"
      else
        "(#{list.join(" ")}#{" checked" if chance(0.3)})"
      end
    end

    def attribute
      name = pick(%w[class id title href data aria name])
      case @random.rand(8)
      when 0 then %(#{name}="#{text}")
      when 1 then %(#{name}="x\#{value}y")
      when 2 then %(#{name}=="\#{value}")
      when 3 then "#{name}=#{pick(EXPRESSIONS + %w[true false nil classes data_hash])}"
      when 4 then "#{name}==#{pick(EXPRESSIONS)}"
      when 5 then "*attributes_hash"
      when 6 then %(#{name}=(flag ? "on" : "off"))
      else %(#{name}="")
      end
    end

    def text
      pick(["plain", "a & b < c", "with \#{value}", "raw \#{{value}}", "escaped \\\#{value}", "", "multi  space"])
    end
  end

  def test_slim_and_super_slim_render_the_same
    generator = Generator.new(Random.new(SEED))
    sources = Array.new(CASE_COUNT) { generator.template }
    renderings = SuperSlim::Parallel.map(sources, minimum_per_process: 500) { |source| [render(:slim, source), render(:super_slim, source)] }
    sources.zip(renderings).each_with_index do |(source, (slim_html, super_slim_html)), index|
      assert_equal slim_html, super_slim_html, "Case #{index} (seed #{SEED}):\n#{source}"
    end
  end

  # The formatter raises UnsafeFormattingError rather than change a rendering: here it must never have to.
  def test_formatting_keeps_the_rendering_and_is_idempotent
    random = Random.new(SEED)
    generator = Generator.new(random)
    sources = Array.new(CASE_COUNT) do
      indent_width = 1 + random.rand(4)
      generator.template.gsub(/^( +)/) { " " * ($1.size / 2 * indent_width) }.gsub(/^( *)([-=]+) /, '\1\2')
    end
    formattings = SuperSlim::Parallel.map(sources, minimum_per_process: 500) do |source|
      formatted = SuperSlim::Formatter.call(source)
      [formatted, SuperSlim::Formatter.call(formatted)]
    rescue SuperSlim::SyntaxError
      nil
    end
    sources.zip(formattings).each_with_index do |(source, (formatted, reformatted)), index|
      assert_equal formatted, reformatted, "Case #{index} (seed #{SEED}) is not idempotent:\n#{source}" if formatted
    end
  end

  # Wrapping joins and spreads lines at any length: what it writes, it must write again.
  def test_wrapping_is_idempotent
    random = Random.new(SEED)
    generator = Generator.new(random)
    cases = Array.new(CASE_COUNT) { [generator.template, 20 + random.rand(60)] }
    wrappings = SuperSlim::Parallel.map(cases, minimum_per_process: 500) do |source, max_line_length|
      formatter = SuperSlim::Formatter.new(max_line_length:)
      wrapped = formatter.call(source)
      [wrapped, formatter.call(wrapped)]
    rescue SuperSlim::SyntaxError
      nil
    end
    cases.zip(wrappings).each_with_index do |((source, max_line_length), (wrapped, rewrapped)), index|
      assert_equal wrapped, rewrapped, "Case #{index} (seed #{SEED}) is not idempotent at #{max_line_length} columns:\n#{source}" if wrapped
    end
  end

  private

  def render(engine, source)
    template = if engine == :slim
      Slim::Template.new(format: :html, sort_attrs: false, pretty: false) { source }
    else
      SuperSlim::Template.new { source }
    end
    template.render(Scope.new)
  rescue ::SyntaxError
    "error: invalid Ruby"
  rescue => exception
    "error: #{exception.message.lines.first}"
  end
end
