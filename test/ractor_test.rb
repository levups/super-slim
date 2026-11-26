# frozen_string_literal: true

require "minitest/autorun"
require "super_slim"
require "super_slim/linter"
require "super_slim/rails_handler"
require "erb/version"

Warning[:experimental] = false # Ractor

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
    assert_equal %w[SuperSlim::Formatter::FIELDS_BY_NODE_CLASS SuperSlim::Formatter::COMPARATOR_BY_NODE_CLASS].sort, unshareable.sort
  end

  def test_the_rails_handler_can_be_shared
    assert Ractor.shareable?(SuperSlim::RailsHandler.new.freeze)
  end

  def test_compiles_in_a_ractor
    skip_unless_erb_escapes_in_ractors
    assert_equal SuperSlim.compile(SOURCE, file: "page.slim"), in_ractor { SuperSlim.compile(RactorTest::SOURCE, file: "page.slim") }
  end

  def test_renders_in_a_ractor
    skip_unless_erb_escapes_in_ractors
    Page.class_eval("def render\n#{SuperSlim.compile(SOURCE, file: "page.slim")}\nend", __FILE__, __LINE__)

    assert_equal Page.new("Posts", Page.posts).render, in_ractor { RactorTest::Page.new("Posts", RactorTest::Page.posts).render }
  end

  def test_formats_in_a_ractor
    skip_unless_erb_escapes_in_ractors
    source = "div\n  p= title\n  - if  posts.any?\n    span(class=\"a\")  Hello\n"

    assert_equal SuperSlim::Formatter.call(source), in_ractor(source) { SuperSlim::Formatter.call(_1) }
  end

  def test_lints_in_a_ractor
    source = "div\n  p= title  \n  div.card Hello\n"
    expected = SuperSlim::Linter.new.call("page.slim", source).map(&:to_s)

    assert_equal expected, in_ractor(source) { SuperSlim::Linter.new.call("page.slim", _1).map(&:to_s) }
  end

  private

  # Compiling escapes static attribute text, and rendering escapes values, with ERB::Escape: Ractor-safe since erb
  # 5.0.2, which Ruby 3.3 and 3.4 don't ship (2026-11). Its VERSION is a private constant before erb 5.
  def skip_unless_erb_escapes_in_ractors
    version = ERB.const_get(:VERSION)
    skip "erb #{version} can't escape outside the main Ractor" if Gem::Version.new(version) < Gem::Version.new("5.0.2")
  end

  def in_ractor(*arguments, &block)
    ractor = Ractor.new(*arguments, &block)
    # 2026-11: Ruby 4.0 replaced Ractor#take with Ractor#value.
    ractor.respond_to?(:value) ? ractor.value : ractor.take
  end

  def constants_of(namespace, seen = {})
    return [] if seen[namespace]

    seen[namespace] = true
    namespace.constants(false).flat_map do |name|
      next [] if namespace.autoload?(name)

      value = namespace.const_get(name, false)
      next constants_of(value, seen) if value.is_a?(Module) && value.name&.start_with?("SuperSlim")

      [["#{namespace}::#{name}", value]]
    end
  end
end
