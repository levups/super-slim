# frozen_string_literal: true

# What script/corpus_check.rb and script/corpus_snapshot.rb share: template formats, error capture, and the stub
# that lets real templates render without their app.
XML_EXTENSIONS = %w[.xml.slim .rss.slim .atom.slim .builder.slim].freeze

# Stands for any helper, local or object a template calls: it renders as text that needs escaping, iterates
# once, yields stubs to blocks and returns what the block returns, so block content is rendered too.
class Stub
  TEXT = "<stub & co>"

  def method_missing(name, *_arguments, **_options, &block)
    return Stub.new unless block

    yielded = yield(Array.new(block.arity.abs.clamp(0, 3)) { Stub.new })
    yielded.is_a?(String) ? yielded : Stub.new
  end

  def respond_to_missing?(name, _include_private = false) = !name.to_s.start_with?("to_")
  def to_s = TEXT
  def to_str = TEXT
  def to_i = 1
  def +(other) = other.is_a?(String) ? TEXT + other : 1
  def coerce(other) = [other, 1]
  def each(&) = [Stub.new].each(&)
  def map(&) = [Stub.new].map(&)
  def each_with_index(&) = [Stub.new].each_with_index(&)
  def to_a = [Stub.new]
  def to_h = {"data-stub" => TEXT}
  def html_safe? = false
  def present? = true
  def blank? = false
  def empty? = false
  def any? = true
  def size = 1
  def count = 1
end

class StubScope < Stub
  def initialize(source)
    source.scan(/@(\w+)/).flatten.uniq.each { |name| instance_variable_set("@#{name}", Stub.new) unless name == "output_buffer" }
  end
end

# Constants of the app (models, Current, namespaces) are a module that answers like a stub, so
# `Admin::Report.model_name` resolves too.
StubConstant = Module.new do
  def self.const_missing(_name) = self
  def self.method_missing(name, *arguments, **options, &) = Stub.new.public_send(name, *arguments, **options, &)
  def self.respond_to_missing?(_name, _include_private = false) = true
end

# A module, not top-level methods: those would become private methods of every object, and a template's
# `render "partial"` would call this script's render.
module Corpus
  module_function

  # Only once templates render: until then, an unknown constant must still raise.
  def stub_missing_constants!
    def Object.const_missing(_name) = StubConstant
  end

  def format_of(path) = (XML_EXTENSIONS.any? { path.end_with?(_1) }) ? :xml : :html

  def outcome
    yield
  rescue StandardError, ScriptError => exception
    "error: #{exception.class}"
  end

  def compile_error_or
    yield
  rescue StandardError, ScriptError => exception
    "error: #{exception.class.name.split("::").last}: #{exception.message.lines.first.to_s.strip}"
  end

  # Inside a lambda, a template's own `- return` ends the template, not this script's method.
  def render(code, path, source)
    outcome { StubScope.new(source).instance_eval("-> {\n#{code}\n}.call", __FILE__, __LINE__).to_s }
  end

  def render_with_slim(source, path)
    render(Slim::Engine.new(format: format_of(path), sort_attrs: false, pretty: false).call(source), path, source)
  end

  def render_with_slimx(source, path)
    render(SlimX.compile(source, file: path, format: format_of(path), strict: false), path, source)
  end
end
