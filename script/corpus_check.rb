# frozen_string_literal: true

# Checks SlimX against every .slim file of real projects.
#   ruby -Ilib script/corpus_check.rb [--render] [--report report.json] DIRECTORY...
#
# For each template:
# - Slim and SlimX both compile it, or both refuse it;
# - SlimX's Ruby parses, and every `-` and `=` sits on its template line, for backtraces;
# - slimx fmt is idempotent, and refuses to write a template whose Ruby would change;
# - the linter runs; its offenses go to the report, so two versions can be compared.
#
# --render also renders each template through Slim 5 and SlimX against a stub that answers every helper, local
# and constant, and requires the same HTML, before and after formatting. Rendering runs the template's Ruby:
# pass it only for directories you trust, such as your own app, never for downloaded projects.
require "active_support/all"
require "json"
require "prism"
require "slim"
require "slimx"
require "slimx/linter"
require "slimx/parallel"

require_relative "corpus_support"

render = !ARGV.delete("--render").nil?
Corpus.stub_missing_constants! if render
report_path = ARGV.delete_at(ARGV.index("--report") + 1).tap { ARGV.delete("--report") } if ARGV.include?("--report")
paths = ARGV.flat_map { Dir[File.join(File.expand_path(it), "**/*.slim")] }.sort
abort "No .slim file under #{ARGV.join(", ")}" if paths.empty?

linter = SlimX::Linter.new
CHECKS = %i[compile prism lines render format idempotence format_render lint].freeze

# Everything one template tells, built in a worker process: failures as [check, message] pairs.
results = SlimX::Parallel.map(paths, minimum_per_process: 200) do |path|
  source = File.read(path)
  failures = []
  result = { path:, failures:, slim_unavailable: false, dropped_feature: false, rendered: false, render_error: nil }

  slim_code = Corpus.compile_error_or { Slim::Engine.new(format: Corpus.format_of(path), sort_attrs: false).call(source) }
  slimx_code = Corpus.compile_error_or { SlimX.compile(source, file: path, format: Corpus.format_of(path), strict: false) }
  slim_compiles = !slim_code.start_with?("error:")
  slimx_compiles = !slimx_code.start_with?("error:")
  # Slim may lack an optional gem here (pandoc-ruby for markdown:), and SlimX refuses what it dropped on purpose.
  if !slim_compiles && slim_code.include?("LoadError")
    result[:slim_unavailable] = true
  elsif slim_compiles && slimx_code.include?("not supported")
    result[:dropped_feature] = true
  elsif slim_compiles != slimx_compiles
    failures << [:compile, "#{path}: #{slim_compiles ? "Slim compiles" : "Slim #{slim_code}"}; #{slimx_compiles ? "SlimX compiles" : "SlimX #{slimx_code}"}"]
  end

  if slimx_compiles
    parse_errors = Prism.parse("def template\n#{slimx_code}\nend").errors
    slim_parses = slim_compiles && Prism.parse("def template\n#{slim_code}\nend").errors.empty?
    failures << [:prism, "#{path}: #{parse_errors.first.message}"] if parse_errors.any? && slim_parses

    parser = SlimX::Parser.new(file: path, outline: true)
    parser.call(source)
    generated_lines = slimx_code.lines
    misplaced = parser.line_by_node.find do |node, lineno|
      next false unless node.is_a?(SlimX::AST::Control) || node.is_a?(SlimX::AST::Output)

      first_code_line = node.code.lines.first.to_s.strip
      !first_code_line.empty? && !generated_lines[lineno - 1].to_s.include?(first_code_line)
    end
    failures << [:lines, "#{path}:#{misplaced[1]}: `#{misplaced[0].code.lines.first.strip[0, 60]}` is not on its line"] if misplaced

    if render
      slim_html = Corpus.render_with_slim(source, path)
      slimx_html = Corpus.render_with_slimx(source, path)
      failures << [:render, "#{path}: Slim #{slim_html[0, 80]} / SlimX #{slimx_html[0, 80]}"] if slim_html != slimx_html
      result[:rendered] = !slimx_html.start_with?("error:")
      result[:render_error] = slimx_html if slimx_html.start_with?("error:")
    end
  end

  formatted = Corpus.outcome { SlimX::Formatter.new.call(source) }
  if formatted.start_with?("error:")
    failures << [:format, "#{path}: #{formatted}"] if slimx_compiles
  else
    failures << [:idempotence, path] unless SlimX::Formatter.new.call(formatted) == formatted
    failures << [:format_render, path] if render && slimx_compiles && Corpus.render_with_slimx(formatted, path) != slimx_html
  end

  offenses = Corpus.outcome { linter.call(path, source) }
  if offenses.is_a?(String)
    failures << [:lint, "#{path}: #{offenses}"]
    offenses = []
  end
  result.merge(
    compiles: slimx_compiles,
    reformatted: !formatted.start_with?("error:") && formatted != source,
    offenses: offenses.map { "#{it.lineno}: [#{it.rule}] #{it.message}" },
    offense_rules: offenses.map(&:rule)
  )
end

messages_by_check = results.flat_map { it[:failures] }.group_by(&:first).transform_values { it.map(&:last) }
offense_count_by_rule = results.flat_map { it[:offense_rules] }.tally
render_error_count_by_class = results.filter_map { it[:render_error] }.tally

puts "#{paths.size} templates"
puts "Rendered against the stub: #{render ? results.count { it[:rendered] } : "skipped, --render runs the templates"} (#{render_error_count_by_class.sort_by { -it[1] }.first(5).map { "#{it[0]} #{it[1]}" }.join(", ")})"
puts "Slim cannot compile here (missing optional gem): #{results.count { it[:slim_unavailable] }}; refused by SlimX on purpose: #{results.count { it[:dropped_feature] }}"
puts "Reformatted by slimx fmt: #{results.count { it[:reformatted] }}"
puts "Lint offenses: #{offense_count_by_rule.sort_by { -it[1] }.map { "#{it[0]} #{it[1]}" }.join(", ")}"
CHECKS.each do |check|
  messages = messages_by_check.fetch(check, [])
  puts "#{check}: #{messages.size} failures"
  messages.first(Integer(ENV.fetch("SHOW", 10))).each { puts "  #{it}" }
end
File.write(report_path, JSON.pretty_generate(results.to_h { [it[:path], it.slice(:compiles, :reformatted, :offenses)] })) if report_path
exit(messages_by_check.empty? ? 0 : 1)
