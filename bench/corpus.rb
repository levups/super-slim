# frozen_string_literal: true

# Compiles every .slim file under the given directory with Slim (configured like a Rails app) and SlimX,
# checks SlimX's Ruby is valid, and reports compile time and allocations.
#   ruby -Ilib bench/corpus.rb path/to/app
require "prism"
require "slim"
require "slimx"

directory = ARGV.fetch(0)
templates = Dir[File.join(directory, "**/*.slim")].sort.to_h { |path| [path, File.read(path)] }
XML_EXTENSIONS = %w[.rss.slim .atom.slim .xml.slim].freeze
format_by_path = templates.keys.to_h { |path| [path, (XML_EXTENSIONS.any? { path.end_with?(_1) }) ? :xml : :html] }

Temple::Generators::RailsOutputBuffer.set_options(capture_generator: Temple::Generators::StringBuffer)
Slim::Engine.remove :StaticAnalyzer
slim_engine_by_format = %i[html xml].to_h do |format|
  [format, Slim::Engine.new(format:, sort_attrs: false, pretty: false, generator: Temple::Generators::RailsOutputBuffer,
    disable_capture: true, use_html_safe: true)]
end
compile_with_slim = ->(path, source) { slim_engine_by_format.fetch(format_by_path[path]).call(source) }
compile_with_slimx = ->(path, source) { SlimX.compile(source, file: path, format: format_by_path[path], rails: true, html_safe: true) }

failures = templates.filter_map do |path, source|
  code = compile_with_slimx.call(path, source)
  errors = Prism.parse("def template\n#{code}\nend").errors
  "#{path}: #{errors.first.message}" if errors.any?
rescue => exception
  "#{path}: #{exception.class}: #{exception.message.lines.first}"
end
puts failures.first(20), "#{failures.size} failures / #{templates.size} templates"

# Both engines time the same templates: the ones each compiles (Slim needs gems for some embedded engines).
compiled_by_both = templates.select do |path, source|
  compile_with_slim.call(path, source)
  compile_with_slimx.call(path, source)
rescue StandardError, LoadError
  false
end
puts "#{compiled_by_both.size} templates compiled by both, timed below"

def measure(label, templates, compiler)
  3.times { templates.each { |path, source| compiler.call(path, source) } }
  GC.start
  allocations = GC.stat(:total_allocated_objects)
  started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
  5.times { templates.each { |path, source| compiler.call(path, source) } }
  milliseconds = (Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at) * 1000 / 5
  printf("%-9s %7.1f ms  %9d allocations per corpus\n", label, milliseconds, (GC.stat(:total_allocated_objects) - allocations) / 5)
end

measure("Slim", compiled_by_both, compile_with_slim)
measure("SlimX", compiled_by_both, compile_with_slimx)
