# frozen_string_literal: true

# Compares two SlimX revisions over a corpus, as RuboCop's corpus_diff does: the working tree against a base
# revision checked out in a temporary git worktree, each run in its own Ruby process.
#   ruby script/corpus_diff.rb [--base REV] [--render] DIRECTORY...
#
# Reports templates whose compiled Ruby changed (expected on optimizations), whose compile status flipped, whose
# formatting changed, and lint offenses that appeared or disappeared. Fails when a template stops compiling or
# formats differently, and with --render when it renders different HTML. --render runs the templates' Ruby:
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

# Gems come from this checkout's bundle; SlimX comes from the revision's lib, first on the load path.
def snapshot(lib_directory, directories, render)
  environment = ENV.to_h.select { |name, _| name == "RUBYOPT" || name.start_with?("BUNDLE_") }.transform_values { nil }
  environment["BUNDLE_GEMFILE"] = File.join(ROOT, "Gemfile")
  command = ["bundle", "exec", "ruby", "-I", lib_directory, File.join(ROOT, "script/corpus_snapshot.rb"), *("--render" if render), *directories]
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
base = ARGV.include?("--base") ? ARGV.delete_at(ARGV.index("--base") + 1).tap { ARGV.delete("--base") } : default_base
directories = ARGV.map { File.expand_path(_1) }
abort "Usage: ruby script/corpus_diff.rb [--base REV] [--render] DIRECTORY..." if directories.empty?

base_sha = git("rev-parse", "--verify", "#{base}^{commit}")
before, after = Dir.mktmpdir("slimx-corpus-diff") do |temporary_directory|
  worktree = File.join(temporary_directory, "base")
  git("worktree", "add", "--detach", worktree, base_sha)
  [snapshot(File.join(worktree, "lib"), directories, render), snapshot(File.join(ROOT, "lib"), directories, render)]
ensure
  git("worktree", "remove", "--force", worktree) if worktree && File.directory?(worktree)
end

paths = (before.keys | after.keys).sort
relative = ->(path) { directories.reduce(path) { |shortened, directory| shortened.delete_prefix("#{File.dirname(directory)}/") } }
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
report("Formatting changed", formatting_changed.map(&relative), failing: true)
report("Rendered HTML changed", html_changed.map(&relative), failing: true)
report("Compiled Ruby changed", compiled_changed.map(&relative), failing: false)
offense_changes_by_rule.sort.each do |rule, changes|
  changes.each { |change, examples| report("#{rule} offenses #{change}", examples, failing: false) }
end
puts "No difference" if [stopped_compiling, started_compiling, formatting_changed, html_changed, compiled_changed].all?(&:empty?) &&
  offense_changes_by_rule.empty?
exit([stopped_compiling, formatting_changed, html_changed].all?(&:empty?) ? 0 : 1)
