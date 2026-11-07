# frozen_string_literal: true

# Compares two SuperSlim revisions over a corpus, as RuboCop's corpus_diff does: the working tree against a base
# revision checked out in a temporary git worktree, each run in its own Ruby process.
#   ruby script/corpus_diff.rb [--base REV] [--render] [--formatting-changes] DIRECTORY...
#
# Reports templates whose compiled Ruby changed (expected on optimizations), whose compile status flipped, whose
# formatting changed, and lint offenses that appeared or disappeared. Fails when a template stops compiling or
# formats differently, unless --formatting-changes says the change means to, and with --render when it renders
# different HTML. Formatting changes are shown as diffs, and in the job summary on GitHub Actions. --render runs the templates' Ruby:
# only for directories you trust.
require "json"
require "open3"
require "tmpdir"

ROOT = File.expand_path("..", __dir__)
EXAMPLE_COUNT = 5

def git(*arguments)
  output, status = Open3.capture2e("git", "-C", ROOT, *arguments)
  abort "git #{arguments.join(" ")} failed:\n#{output}" unless status.success?
  output.strip
end

def default_base
  _, status = Open3.capture2e("git", "-C", ROOT, "rev-parse", "--verify", "--quiet", "origin/main")
  status.success? ? "origin/main" : "main"
end

# Gems come from this checkout's bundle; SuperSlim comes from the revision's lib, first on the load path.
def snapshot(lib_directory, directories, render, formatted: false)
  environment = ENV.to_h.select { |name, _| name == "RUBYOPT" || name.start_with?("BUNDLE_") }.transform_values { nil }
  environment["BUNDLE_GEMFILE"] = File.join(ROOT, "Gemfile")
  command = ["bundle", "exec", "ruby", "-I", lib_directory, File.join(ROOT, "script/corpus_snapshot.rb"), *("--render" if render), *("--formatted" if formatted), *directories]
  output, errors, status = Open3.capture3(environment, *command, chdir: ROOT)
  abort "Snapshot with #{lib_directory} failed:\n#{errors}" unless status.success?
  JSON.parse(output)
end

def compiles?(record) = !record["tilt"].start_with?("error:")

def report(title, paths, failing:)
  return if paths.empty?

  puts "#{title}: #{paths.size}#{" (fails)" if failing}"
  paths.first(EXAMPLE_COUNT).each { puts "  #{_1}" }
end

render = !ARGV.delete("--render").nil?
formatting_changes = !ARGV.delete("--formatting-changes").nil?
base = ARGV.include?("--base") ? ARGV.delete_at(ARGV.index("--base") + 1).tap { ARGV.delete("--base") } : default_base
directories = ARGV.map { File.expand_path(_1) }
abort "Usage: ruby script/corpus_diff.rb [--base REV] [--render] [--formatting-changes] DIRECTORY..." if directories.empty?

# The unified diff of two formattings of a template, labeled with its path.
def formatting_diff(path, before, after)
  Dir.mktmpdir("super-slim-corpus-diff") do |directory|
    File.write(before_file = File.join(directory, "before"), before)
    File.write(after_file = File.join(directory, "after"), after)
    output, = Open3.capture2("diff", "-u", "--label", "a/#{path}", "--label", "b/#{path}", before_file, after_file)
    output
  end
end

base_sha = git("rev-parse", "--verify", "#{base}^{commit}")
relative = ->(path) { directories.reduce(path) { |shortened, directory| shortened.delete_prefix("#{File.dirname(directory)}/") } }
before, after, formatting_diffs = Dir.mktmpdir("super-slim-corpus-diff") do |temporary_directory|
  worktree = File.join(temporary_directory, "base")
  git("worktree", "add", "--detach", worktree, base_sha)
  before = snapshot(File.join(worktree, "lib"), directories, render)
  after = snapshot(File.join(ROOT, "lib"), directories, render)
  changed = before.keys.select { |path| after[path] && before[path]["fmt"] != after[path]["fmt"] }.sort
  diffs = []
  if changed.any?
    formatted_before = snapshot(File.join(worktree, "lib"), changed, false, formatted: true)
    formatted_after = snapshot(File.join(ROOT, "lib"), changed, false, formatted: true)
    diffs = changed.map { formatting_diff(relative.call(_1), formatted_before[_1], formatted_after[_1]) }
  end
  [before, after, diffs]
ensure
  git("worktree", "remove", "--force", worktree) if worktree && File.directory?(worktree)
end

paths = (before.keys | after.keys).sort
stopped_compiling = paths.select { |path| before[path] && after[path] && compiles?(before[path]) && !compiles?(after[path]) }
started_compiling = paths.select { |path| before[path] && after[path] && !compiles?(before[path]) && compiles?(after[path]) }
compiled_changed = paths.select do |path|
  before[path] && after[path] && compiles?(before[path]) && compiles?(after[path]) &&
    before[path].values_at("tilt", "rails") != after[path].values_at("tilt", "rails")
end
formatting_changed = paths.select { |path| before[path] && after[path] && before[path]["fmt"] != after[path]["fmt"] }
html_changed = render ? paths.select { |path| before[path] && after[path] && before[path]["html"] != after[path]["html"] } : []

offense_changes_by_rule = Hash.new { |hash, rule| hash[rule] = {appeared: [], disappeared: []} }
paths.each do |path|
  next unless before[path] && after[path]

  before_offenses, after_offenses = before[path]["lint"], after[path]["lint"]
  next if before_offenses == after_offenses

  {appeared: after_offenses - Array(before_offenses), disappeared: before_offenses - Array(after_offenses)}.each do |change, offenses|
    next unless offenses.is_a?(Array)

    offenses.each { |offense| offense_changes_by_rule[offense[/\A[^:]+/]][change] << "#{relative.call(path)}:#{offense[/:(\d+):/, 1]} #{offense[/: (.*)\z/, 1]}" }
  end
end

puts "#{paths.size} templates, #{base} (#{base_sha[0, 8]}) against the working tree"
report("Stopped compiling", stopped_compiling.map(&relative), failing: true)
report("Started compiling", started_compiling.map(&relative), failing: false)
report("Formatting changed", formatting_changed.map(&relative), failing: !formatting_changes)
report("Rendered HTML changed", html_changed.map(&relative), failing: true)
report("Compiled Ruby changed", compiled_changed.map(&relative), failing: false)
offense_changes_by_rule.sort.each do |rule, changes|
  changes.each { |change, examples| report("#{rule} offenses #{change}", examples, failing: false) }
end
if formatting_diffs.any?
  puts "", *formatting_diffs
  if (summary = ENV["GITHUB_STEP_SUMMARY"])
    # GitHub shows up to 1 MiB of summary per step.
    shown = formatting_diffs.each_with_object([]) { |diff, kept| kept << diff if kept.sum(&:bytesize) + diff.bytesize < 900_000 }
    File.open(summary, "a") do |file|
      file.puts "### Formatting changed in #{formatting_diffs.size} templates", ""
      file.puts "#{shown.size} shown here, all in the job log.", "" if shown.size < formatting_diffs.size
      shown.each { |diff| file.puts "```diff", diff, "```", "" }
    end
  end
end
puts "No difference" if [stopped_compiling, started_compiling, formatting_changed, html_changed, compiled_changed].all?(&:empty?) &&
  offense_changes_by_rule.empty?
exit([stopped_compiling, (formatting_changed unless formatting_changes), html_changed].compact.all?(&:empty?) ? 0 : 1)
