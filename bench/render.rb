# frozen_string_literal: true

# Renders the same templates through Slim (configured like a production app) and SlimX inside Action View.
#   bundle exec ruby -Ilib bench/render.rb            # interpreter
#   bundle exec ruby --yjit -Ilib bench/render.rb     # YJIT
require "action_dispatch"
require "action_view"
require "benchmark/ips"
require "slim"
require "slimx"
require "slimx/rails_handler"
require "tmpdir"

Temple::Generators::RailsOutputBuffer.set_options(capture_generator: Temple::Generators::StringBuffer)
Slim::Engine.remove :StaticAnalyzer
module Temple::Utils
  def escape_html(html) = ::ERB::Escape.html_escape(html.to_s)
end
Temple::Templates::Rails(Slim::Engine, register_as: :slim, generator: Temple::Generators::RailsOutputBuffer,
  disable_capture: true, streaming: true, format: :html, sort_attrs: false, pretty: false)
ActionView::Template.register_template_handler(:slimx, SlimX::RailsHandler.new)

posts = Array.new(24) do |index|
  {id: index, title: "Hello <World> no. #{index}", url: "/posts/#{index}", image: "/images/#{index}.webp",
   comments: "1,299", featured: index.even?, draft: index % 5 == 0, tags: (index % 3 == 0) ? %w[new popular] : []}
end
fields = Array.new(12) do |index|
  {id: "field_#{index}", label: "Field #{index}", name: "user[field_#{index}]", value: "value & #{index}",
   hint: "Hint", html: {required: index.even?, placeholder: "…", autocomplete: "off"}, data: {controller: "input", index:}}
end
locals = {posts:, fields:}

Dir.mktmpdir do |directory|
  Dir[File.join(__dir__, "templates/*.slim")].each do |path|
    name = File.basename(path, ".slim")
    File.write(File.join(directory, "#{name}.html.slim"), File.read(path))
    File.write(File.join(directory, "#{name}.html.slimx"), File.read(path))
  end
  view = ActionView::Base.with_empty_template_cache.with_view_paths([directory])

  render = ->(name, handler) { view.render(template: name, handlers: [handler], locals:) }
  %w[post_list form_fields].each do |name|
    raise "#{name}: outputs differ" unless render.call(name, :slim) == render.call(name, :slimx)

    puts "", "#{name} (#{RubyVM::YJIT.enabled? ? "YJIT" : "interpreter"})"
    %i[slim slimx].each do |handler|
      render.call(name, handler)
      allocations = GC.stat(:total_allocated_objects)
      100.times { render.call(name, handler) }
      puts format("  %-6s %6d allocations per render", handler, (GC.stat(:total_allocated_objects) - allocations) / 100)
    end
    next if ENV["ALLOCATIONS_ONLY"]

    Benchmark.ips(quiet: true) do |benchmark|
      benchmark.config(time: 3, warmup: 1)
      %i[slim slimx].each { |handler| benchmark.report(handler.to_s) { render.call(name, handler) } }
      benchmark.compare!
    end
  end
end
