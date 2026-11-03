# frozen_string_literal: true

# Replays Slim's own test suite as a differential test: every template renders through Slim (configured like a
# modern Rails app: HTML5, no sorting, no pretty) and through SlimX, and both outputs must match byte for byte.
require "minitest/autorun"
require "slim"
require "slimx/tilt"

SLIM_TEST_DIRECTORY = File.join(Gem.loaded_specs.fetch("slim").full_gem_path, "test/core")
helper_source = File.read(File.join(SLIM_TEST_DIRECTORY, "helper.rb"))
eval(helper_source[helper_source.index("class Env")..], TOPLEVEL_BINDING, File.join(SLIM_TEST_DIRECTORY, "helper.rb")) # rubocop:disable Security/Eval -- Slim's own test helper

class TestSlim < Minitest::Test
  REFERENCE_OPTIONS = {format: :html, sort_attrs: false, pretty: false}.freeze
  SLIMX_OPTIONS = %i[file shortcut format].freeze
  NEUTRAL_OPTIONS = {format: :html, sort_attrs: false, pretty: false, use_html_safe: nil}.freeze

  def setup
    @env = Env.new
  end

  def render(source, options = {}, &block)
    slim_html = render_with_slim(source, options, &block)
    slimx_html = render_with_slimx(source, options, &block)
    assert_equal slim_html, slimx_html, "SlimX differs from Slim on:\n#{source}"
    slimx_html
  end

  def render_with_slim(source, options = {}, &block)
    options = options.dup
    scope = options.delete(:scope)
    locals = options.delete(:locals)
    Slim::Template.new(options[:file], REFERENCE_OPTIONS.merge(options)) { source }.render(scope || Env.new, locals, &block)
  end

  def render_with_slimx(source, options = {}, &block)
    options = options.dup
    scope = options.delete(:scope)
    locals = options.delete(:locals)
    skip_unsupported(options)
    slimx_options = options.slice(*SLIMX_OPTIONS)
    slimx_options[:shortcuts] = slimx_options.delete(:shortcut) if slimx_options.key?(:shortcut)
    slimx_options[:html_safe] = options[:use_html_safe] if options.key?(:use_html_safe)
    SlimX::Template.new(options[:file], slimx_options) { source }.render(scope || Env.new, locals, &block)
  end

  def skip_unsupported(options)
    options = (Slim::Engine.thread_options || {}).to_hash.merge(options)
    unsupported = options.keys - SLIMX_OPTIONS - %i[use_html_safe] - NEUTRAL_OPTIONS.keys
    unsupported << :format unless [nil, :html, :xml].include?(options[:format])
    unsupported += %i[sort_attrs pretty].select { options[it] }
    skip "Unsupported options #{unsupported.uniq.inspect}" if unsupported.any?
  end

  class HtmlSafeString < String
    def html_safe? = true
    def to_s = self
  end

  def with_html_safe
    String.send(:define_method, :html_safe?) { false }
    String.send(:define_method, :html_safe) { HtmlSafeString.new(self) }
    yield
  ensure
    String.send(:undef_method, :html_safe?) if String.method_defined?(:html_safe?)
    String.send(:undef_method, :html_safe) if String.method_defined?(:html_safe)
  end

  def assert_html(_expected, source, options = {}, &block)
    render(source, options, &block)
  end

  def assert_syntax_error(message, source, options = {})
    render_with_slimx(source, options)
    raise "Syntax error expected"
  rescue SlimX::SyntaxError => exception
    assert_equal message, exception.message
    message =~ /([^\s]+), Line (\d+)/
    assert_backtrace exception, "#{$1}:#{$2}"
  end

  def assert_ruby_error(error, from, source, options = {})
    render_with_slimx(source, options)
    raise "Ruby error expected"
  rescue error => exception
    assert_backtrace(exception, from)
  end

  def assert_backtrace(exception, from)
    exception.backtrace[0] =~ /([^\s]+:\d+)/
    assert_equal from, $1
  end

  def assert_ruby_syntax_error(from, source, options = {})
    render_with_slimx(source, options)
    raise "Ruby syntax error expected"
  rescue ::SyntaxError => exception
    exception.message =~ /([^\s]+:\d+):/
    assert_equal from, $1
  end

  def assert_runtime_error(message, source, options = {})
    render_with_slimx(source, options)
    flunk "Runtime error expected"
  rescue RuntimeError, SlimX::Error => exception
    assert_equal message, exception.message
  end
end
