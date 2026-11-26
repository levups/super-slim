# frozen_string_literal: true

require "minitest/autorun"
require "open3"
require "prism"
require "rbconfig"
require "super_slim"
require "super_slim/linter"
require "erb/version"

# Compiling, rendering, formatting and linting from a Ractor other than the main one, as Rails may one day do.
class RactorTest < Minitest::Test
  SOURCE = <<~'SLIM'
    main.blog
      h1 = title
      - posts.each do |post|
        article.card class=("featured" if post[:featured]) data-id=post[:id] *post[:extra]
          a href=post[:url] data=post[:data] = post[:title]
          *{tag: post[:tag]} Hello
          li class=[post[:a], post[:b]] class="tag tag-#{post[:id]}"
  SLIM
  # A rewrite the formatter checks against the compiled Ruby, and a line it wraps.
  NEGATED_IF = "- if !x\n  p Hi\n"
  LONG_LINE = %(a.btn.btn-primary.btn-lg href=post_path(post) title=post.title data-turbo-method="delete" data-confirm="Are you sure?" Delete\n)
  LINTED = "div\n  p= title  \n  div.card Hello\n"

  class Page
    def initialize(title, posts)
      @title = title
      @posts = posts
    end

    attr_reader :title, :posts

    def self.posts
      [
        {id: 1, featured: true, url: "/a", title: "Hello <World>", extra: {rel: "nofollow"}, data: {x: 1, y: {z: 2}}, tag: "span", a: "x", b: nil},
        {id: 2, featured: false, url: "/b", title: "Post", extra: {}, data: {}, tag: nil, a: ["p", ["q"]], b: "r"}
      ]
    end
  end

  def setup
    skip "no Ractor on #{RUBY_ENGINE}" unless defined?(Ractor)
  end

  def test_every_constant_can_be_shared
    require "super_slim/cli"
    require "super_slim/formatter"
    unshareable = constants_of(SuperSlim).reject { |_name, value| Ractor.shareable?(value) }.map(&:first)

    # The formatter's caches stay mutable on the main Ractor: other Ractors fill caches of their own.
    assert_equal %w[SuperSlim::Formatter::COMPARATOR_BY_NODE_CLASS SuperSlim::Formatter::FIELDS_BY_NODE_CLASS], unshareable.sort
  end

  def test_compiles_in_a_ractor
    skip_unless_ractors_can_escape_and_parse
    assert_equal SuperSlim.compile(SOURCE, file: "page.slim"), in_ractor { SuperSlim.compile(RactorTest::SOURCE, file: "page.slim") }
  end

  def test_renders_in_a_ractor
    skip_unless_ractors_can_escape_and_parse
    Page.class_eval("def render\n#{SuperSlim.compile(SOURCE, file: "page.slim")}\nend", __FILE__, __LINE__)

    assert_equal Page.new("Posts", Page.posts).render, in_ractor { RactorTest::Page.new("Posts", RactorTest::Page.posts).render }
  end

  def test_formats_in_a_ractor
    skip_unless_ractors_can_escape_and_parse
    expected = [SuperSlim::Formatter.call(NEGATED_IF), SuperSlim::Formatter.new(max_line_length: 60).call(LONG_LINE)]

    assert_equal expected, in_ractor { [SuperSlim::Formatter.call(RactorTest::NEGATED_IF), SuperSlim::Formatter.new(max_line_length: 60).call(RactorTest::LONG_LINE)] }
  end

  def test_a_shareable_formatter_leaves_the_caches_mutable
    Ractor.make_shareable(SuperSlim::Formatter.new)

    assert_equal "- unless x\n  p Hi\n", SuperSlim::Formatter.call(NEGATED_IF)
  end

  def test_lints_in_a_ractor
    skip_unless_ractors_can_escape_and_parse
    expected = SuperSlim::Linter.new.call("page.slim", LINTED).map(&:to_s)

    assert_equal expected, in_ractor { SuperSlim::Linter.new.call("page.slim", RactorTest::LINTED).map(&:to_s) }
  end

  # 2026-11: Ruby 3.3 can't autoload outside the main Ractor, so the README asks it to require the formatter first.
  def test_lints_and_formats_in_a_ractor_of_a_fresh_process
    skip_unless_ractors_can_escape_and_parse
    script = <<~RUBY
      Warning[:experimental] = false
      require "super_slim"
      require "super_slim/linter"
      require "super_slim/formatter" if RUBY_VERSION < "3.4"
      ractor = Ractor.new do
        [SuperSlim::Linter.new.call("page.slim", #{LINTED.dump}).size, SuperSlim::Formatter.call(#{NEGATED_IF.dump})]
      end
      p(ractor.respond_to?(:value) ? ractor.value : ractor.take)
    RUBY
    output, errors, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-e", script)

    assert status.success?, errors
    assert_equal %([#{SuperSlim::Linter.new.call("page.slim", LINTED).size}, #{SuperSlim::Formatter.call(NEGATED_IF).dump}]\n), output
  end

  private

  # 2026-11: outside the main Ractor, escaping needs erb 5.0.2 and parsing Prism 1.5, which Ruby 3.3 doesn't ship.
  # Compiling escapes static attribute text, rendering escapes values, formatting and linting parse Ruby.
  # erb's VERSION is a private constant before erb 5.
  def skip_unless_ractors_can_escape_and_parse
    erb_version = ERB.const_get(:VERSION)
    skip "erb #{erb_version} can't escape outside the main Ractor" if Gem::Version.new(erb_version) < Gem::Version.new("5.0.2")
    skip "Prism #{Prism::VERSION} can't parse outside the main Ractor" if Gem::Version.new(Prism::VERSION) < Gem::Version.new("1.5.0")
  end

  def in_ractor(&block)
    experimental = Warning[:experimental]
    Warning[:experimental] = false
    ractor = Ractor.new(&block)
    # 2026-11: Ruby 4.0 replaced Ractor#take with Ractor#value.
    ractor.respond_to?(:value) ? ractor.value : ractor.take
  ensure
    Warning[:experimental] = experimental
  end

  def constants_of(namespace, visited_namespaces = Set.new)
    return [] unless visited_namespaces.add?(namespace)

    namespace.constants(false).flat_map do |name|
      next [] if namespace.autoload?(name)

      value = namespace.const_get(name, false)
      next constants_of(value, visited_namespaces) if value.is_a?(Module) && value.name&.start_with?("SuperSlim")

      [["#{namespace}::#{name}", value]]
    end
  end
end
