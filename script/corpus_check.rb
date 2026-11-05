# frozen_string_literal: true

# Checks SuperSlim against every .slim file of real projects.
#   ruby -Ilib script/corpus_check.rb [--render] [--report report.json] DIRECTORY...
#
# For each template:
# - Slim and SuperSlim both compile it, or both refuse it;
# - SuperSlim's Ruby parses, and every `-` and `=` sits on its template line, for backtraces;
# - super-slim fmt is idempotent, and refuses to write a template whose Ruby would change;
# - the linter runs; its offenses go to the report, so two versions can be compared.
#
# --render also renders each template through Slim 5 and SuperSlim against a stub that answers every helper, local
# and constant, and requires the same HTML, before and after formatting. Rendering runs the template's Ruby:
# pass it only for directories you trust, such as your own app, never for downloaded projects.
require "active_support/all"
require "json"
require "prism"
require "slim"
require "super_slim"
require "super_slim/linter"
require "super_slim/parallel"

require_relative "corpus_support"

render = !ARGV.delete("--render").nil?
Corpus.stub_missing_constants! if render
report_path = ARGV.delete_at(ARGV.index("--report") + 1).tap { ARGV.delete("--report") } if ARGV.include?("--report")
paths = ARGV.flat_map { Dir[File.join(File.expand_path(_1), "**/*.slim")] }.sort
abort "No .slim file under #{ARGV.join(", ")}" if paths.empty?

linter = SuperSlim::Linter.new
CHECKS = %i[compile prism lines render format idempotence format_render lint].freeze

# Everything one template tells, built in a worker process: failures as [check, message] pairs.
results = SuperSlim::Parallel.map(paths, minimum_per_process: 200) do |path|
  source = File.read(path)
  failures = []
  result = {path:, failures:, slim_unavailable: false, dropped_feature: false, rendered: false, render_error: nil}

  slim_code = Corpus.compile_error_or { Slim::Engine.new(format: Corpus.format_of(path), sort_attrs: false).call(source) }
  super_slim_code = Corpus.compile_error_or { SuperSlim.compile(source, file: path, format: Corpus.format_of(path)) }
  slim_compiles = !slim_code.start_with?("error:")
  super_slim_compiles = !super_slim_code.start_with?("error:")
  # Slim may lack an optional gem here (pandoc-ruby for markdown:), and SuperSlim refuses what it dropped on purpose.
  if !slim_compiles && slim_code.include?("LoadError")
    result[:slim_unavailable] = true
  elsif slim_compiles && super_slim_code.include?("not supported")
    result[:dropped_feature] = true
  elsif slim_compiles != super_slim_compiles
    failures << [:compile, "#{path}: #{slim_compiles ? "Slim compiles" : "Slim #{slim_code}"}; #{super_slim_compiles ? "SuperSlim compiles" : "SuperSlim #{super_slim_code}"}"]
  end

  if super_slim_compiles
    parse_errors = Prism.parse("def template\n#{super_slim_code}\nend").errors
    slim_parses = slim_compiles && Prism.parse("def template\n#{slim_code}\nend").errors.empty?
    failures << [:prism, "#{path}: #{parse_errors.first.message}"] if parse_errors.any? && slim_parses

    parser = SuperSlim::Parser.new(file: path, outline: true)
    parser.call(source)
    generated_lines = super_slim_code.lines
    misplaced = parser.line_by_node.find do |node, lineno|
      next false unless node.is_a?(SuperSlim::AST::Control) || node.is_a?(SuperSlim::AST::Output)

      first_code_line = node.code.lines.first.to_s.strip
      !first_code_line.empty? && !generated_lines[lineno - 1].to_s.include?(first_code_line)
    end
    failures << [:lines, "#{path}:#{misplaced[1]}: `#{misplaced[0].code.lines.first.strip[0, 60]}` is not on its line"] if misplaced

    if render
      slim_html = Corpus.render_with_slim(source, path)
      super_slim_html = Corpus.render_with_super_slim(source, path)
      failures << [:render, "#{path}: Slim #{slim_html[0, 80]} / SuperSlim #{super_slim_html[0, 80]}"] if slim_html != super_slim_html
      result[:rendered] = !super_slim_html.start_with?("error:")
      result[:render_error] = super_slim_html if super_slim_html.start_with?("error:")
    end
  end

  formatted = Corpus.outcome { SuperSlim::Formatter.new.call(source) }
  if formatted.start_with?("error:")
    failures << [:format, "#{path}: #{formatted}"] if super_slim_compiles
  else
    failures << [:idempotence, path] unless SuperSlim::Formatter.new.call(formatted) == formatted
    failures << [:format_render, path] if render && super_slim_compiles && Corpus.render_with_super_slim(formatted, path) != super_slim_html
  end

  offenses = Corpus.outcome { linter.call(path, source) }
  if offenses.is_a?(String)
    failures << [:lint, "#{path}: #{offenses}"]
    offenses = []
  end
  result.merge(
    compiles: super_slim_compiles,
    reformatted: !formatted.start_with?("error:") && formatted != source,
    offenses: offenses.map { |offense| "#{offense.lineno}: [#{offense.rule}] #{offense.message}" },
    offense_rules: offenses.map(&:rule)
  )
end

messages_by_check = results.flat_map { _1[:failures] }.group_by(&:first).transform_values { _1.map(&:last) }
offense_count_by_rule = results.flat_map { _1[:offense_rules] }.tally
render_error_count_by_class = results.filter_map { _1[:render_error] }.tally

puts "#{paths.size} templates"
puts "Rendered against the stub: #{render ? results.count { _1[:rendered] } : "skipped, --render runs the templates"} (#{render_error_count_by_class.sort_by { |_, count| -count }.first(5).map { |error_class, count| "#{error_class} #{count}" }.join(", ")})"
puts "Slim cannot compile here (missing optional gem): #{results.count { _1[:slim_unavailable] }}; refused by SuperSlim on purpose: #{results.count { _1[:dropped_feature] }}"
puts "Reformatted by super-slim fmt: #{results.count { _1[:reformatted] }}"
puts "Lint offenses: #{offense_count_by_rule.sort_by { |_, count| -count }.map { |rule, count| "#{rule} #{count}" }.join(", ")}"
CHECKS.each do |check|
  messages = messages_by_check.fetch(check, [])
  puts "#{check}: #{messages.size} failures"
  messages.first(Integer(ENV.fetch("SHOW", 10))).each { puts "  #{_1}" }
end
File.write(report_path, JSON.pretty_generate(results.to_h { |result| [result[:path], result.slice(:compiles, :reformatted, :offenses)] })) if report_path
exit(messages_by_check.empty? ? 0 : 1)
