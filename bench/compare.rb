# frozen_string_literal: true

# Compiles and renders the same blog page with SuperSlim, Slim, Haml, Erubi and Herb, checks they all render
# the same HTML, and writes the numbers the site shows to docs/benchmarks.json.
#   rake bench                                    # what to run before each release
#   SUPER_SLIM_CORPUS=~/app/views rake bench           # adds the compile time of a whole app's .slim templates
# With corpus/cache fetched (rake corpus:fetch), it also times the public corpus, and super-slim lint and fmt there
# against slim-lint when slim-lint is installed.
require "benchmark/ips"
require "digest"
require "erubi"
require "haml"
require "herb"
require "herb/engine"
require "etc"
require "json"
require "slim"
require "super_slim"

SOURCE_DIRECTORY = File.join(__dir__, "compare")
OUTPUT_PATH = File.expand_path("../docs/benchmarks.json", __dir__)
BENCHMARK_SECONDS = Integer(ENV.fetch("BENCHMARK_SECONDS", 5))

Engine = Data.define(:name, :version, :source_file, :compiler)
ENGINES = [
  Engine.new("SuperSlim", SuperSlim::VERSION, "page.slim", ->(source) { SuperSlim.compile(source, file: "page.slim") }),
  Engine.new("Slim", Slim::VERSION, "page.slim", ->(source) { Slim::Engine.new(format: :html, sort_attrs: false).call(source) }),
  Engine.new("Haml", Haml::VERSION, "page.haml", ->(source) { Haml::Engine.new.call(source) }),
  Engine.new("Erubi", Erubi::VERSION, "page.html.erb", ->(source) { Erubi::Engine.new(source, escape: true).src }),
  Engine.new("Herb", Herb::VERSION, "page.html.erb", ->(source) { Herb::Engine.new(source, escape: true).src })
].freeze

class Page
  def initialize(title:, posts:)
    @title = title
    @posts = posts
  end

  attr_reader :title, :posts
end

page = Page.new(
  title: "Posts & comments",
  posts: Array.new(24) do |index|
    {id: index, title: "Hello <World> no. #{index}", url: "/posts/#{index}", image: "/images/#{index}.webp",
     comments: "1,299", featured: index.even?, draft: (index % 5).zero?, tags: (index % 3).zero? ? %w[new popular] : []}
  end
)

source_by_engine = ENGINES.to_h { |engine| [engine, File.read(File.join(SOURCE_DIRECTORY, engine.source_file))] }
render_method_by_engine = ENGINES.to_h do |engine|
  method_name = :"render_#{engine.name.downcase.tr(" ", "_")}"
  Page.class_eval("def #{method_name}\n#{engine.compiler.call(source_by_engine[engine])}\nend", __FILE__, __LINE__)
  [engine, method_name]
end

html_by_engine = ENGINES.to_h { |engine| [engine, page.public_send(render_method_by_engine[engine]).gsub(/>\s+</, "><").strip] }
reference_html = html_by_engine[ENGINES.first]
html_by_engine.each do |engine, html|
  next if html == reference_html

  offset = [(0...html.size).find { |index| html[index] != reference_html[index] } - 60, 0].max
  raise "#{engine.name} renders different HTML than SuperSlim:\n  #{reference_html[offset, 120]}\n  #{html[offset, 120]}"
end

def allocations_per_call(times = 100, &block)
  yield
  allocations = GC.stat(:total_allocated_objects)
  times.times { yield }
  (GC.stat(:total_allocated_objects) - allocations) / times
end

def iterations_per_second(engines, &block)
  report = Benchmark.ips(quiet: true) do |benchmark|
    benchmark.config(time: BENCHMARK_SECONDS, warmup: 2)
    engines.each { |engine| benchmark.report(engine.name) { yield(engine) } }
  end
  report.entries.to_h { |entry| [entry.label, entry.stats.central_tendency.round] }
end

compiles_per_second = iterations_per_second(ENGINES) { |engine| engine.compiler.call(source_by_engine[engine]) }
renders_per_second = iterations_per_second(ENGINES) { |engine| page.public_send(render_method_by_engine[engine]) }

results = {
  measured_on: Time.now.strftime("%F"),
  ruby: RUBY_DESCRIPTION,
  yjit: defined?(RubyVM::YJIT) && RubyVM::YJIT.enabled?,
  page: "#{page.posts.size} post cards, #{html_by_engine[ENGINES.first].bytesize} bytes of HTML",
  engines: ENGINES.map do |engine|
    {
      name: engine.name,
      version: engine.version,
      compiles_per_second: compiles_per_second.fetch(engine.name),
      compile_allocations: allocations_per_call { engine.compiler.call(source_by_engine[engine]) },
      renders_per_second: renders_per_second.fetch(engine.name),
      render_allocations: allocations_per_call { page.public_send(render_method_by_engine[engine]) }
    }
  end
}

results[:html_sha256] = {"Slim" => Digest::SHA256.hexdigest(page.public_send(render_method_by_engine[ENGINES[1]])),
                          "SuperSlim" => Digest::SHA256.hexdigest(page.public_send(render_method_by_engine[ENGINES[0]]))}

def median_seconds(runs, &block)
  timings = Array.new(runs) do
    started_at = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    yield
    Process.clock_gettime(Process::CLOCK_MONOTONIC) - started_at
  end
  timings.sort[runs / 2]
end

def compile_timings(directory)
  slim_engine = Slim::Engine.new(format: :html, sort_attrs: false)
  templates = Dir[File.join(directory, "**/*.slim")].map { File.read(_1) }.select do |source|
    SuperSlim.compile(source, file: "corpus.slim") && slim_engine.call(source)
  rescue StandardError, ScriptError
    false
  end
  compile_corpus = {
    "SuperSlim" => -> { templates.each { SuperSlim.compile(_1, file: "corpus.slim") } },
    "Slim" => -> { templates.each { slim_engine.call(_1) } }
  }
  {
    templates: templates.size,
    engines: compile_corpus.map do |name, compile|
      2.times { compile.call }
      {name:, milliseconds: (median_seconds(7, &compile) * 1000).round, allocations: allocations_per_call(1, &compile)}
    end
  }
end

PUBLIC_CORPUS_DIRECTORY = File.expand_path("../corpus/cache", __dir__)
corpora = []
corpora << {label: "A production Rails app", **compile_timings(File.expand_path(ENV["SUPER_SLIM_CORPUS"]))} if ENV["SUPER_SLIM_CORPUS"]
if File.directory?(PUBLIC_CORPUS_DIRECTORY)
  application_count = Dir.children(PUBLIC_CORPUS_DIRECTORY).count { File.directory?(File.join(PUBLIC_CORPUS_DIRECTORY, _1)) }
  corpora << {label: "#{application_count} open-source projects", **compile_timings(PUBLIC_CORPUS_DIRECTORY)}
end
results[:corpora] = corpora

# Wall time, and CPU time across processes: super_slim spreads templates over every core, slim-lint uses one.
def command_timing(name, *command)
  system(*command, out: File::NULL, err: File::NULL)
  cpu_before = Process.times
  wall_seconds = median_seconds(3) { system(*command, out: File::NULL, err: File::NULL) }
  cpu_after = Process.times
  cpu_seconds = (cpu_after.cutime + cpu_after.cstime - cpu_before.cutime - cpu_before.cstime) / 3
  {name:, milliseconds: (wall_seconds * 1000).round, cpu_milliseconds: (cpu_seconds * 1000).round}
end

slim_lint = Bundler.with_unbundled_env { `command -v slim-lint`.strip } if defined?(Bundler)
if File.directory?(PUBLIC_CORPUS_DIRECTORY)
  super_slim = [RbConfig.ruby, "--yjit", File.expand_path("../exe/super-slim", __dir__)]
  tools = [
    command_timing("super-slim lint", *super_slim, "lint", PUBLIC_CORPUS_DIRECTORY),
    command_timing("super-slim fmt --check", *super_slim, "fmt", "--check", PUBLIC_CORPUS_DIRECTORY)
  ]
  if slim_lint && !slim_lint.empty?
    version = Bundler.with_unbundled_env { `slim-lint --version`[/[\d.]+/] }
    tools << Bundler.with_unbundled_env do
      command_timing("slim-lint #{version}", slim_lint, "--exclude-linter", "RuboCop", PUBLIC_CORPUS_DIRECTORY)
    end
  end
  results[:tools] = {templates: Dir[File.join(PUBLIC_CORPUS_DIRECTORY, "**/*.slim")].size, processors: Etc.nprocessors, commands: tools}
end

File.write(OUTPUT_PATH, "#{JSON.pretty_generate(results)}\n")
puts File.read(OUTPUT_PATH)
