# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new("test:slimx") do |task|
  task.libs << "lib" << "test"
  task.test_files = FileList["test/*_test.rb"]
end

# A process of its own: Slim's test helper defines and removes String#html_safe? for the whole process.
Rake::TestTask.new("test:slim_suite") do |task|
  task.libs << "lib" << "test" << "test/slim_suite"
  task.test_files = FileList["test/slim_suite/*_test.rb", "test/slim_suite/run.rb"]
end

desc "Run SlimX's tests, then Slim's own suites against SlimX"
task test: %w[test:slimx test:slim_suite]
task default: :test

desc "Compare SlimX with Slim, Haml, Erubi and Herb and write docs/benchmarks.json (run before each release)"
task :bench do
  command = ["ruby", "--yjit", "-Ilib", "bench/compare.rb"]
  command = ["lockf", "-k", ENV["BENCH_LOCK"], *command] if ENV["BENCH_LOCK"]
  sh(*command)
end

desc "Rewrite the linter rules of the website (docs/tools.html) from examples checked against the linter"
task :docs do
  ruby "-Ilib", "script/website_linter_rules.rb"
end

namespace :corpus do
  desc "Download the .slim files of the projects in corpus/manifest.yml into corpus/cache"
  task :fetch do
    ruby "script/corpus_fetch.rb"
  end

  desc "Check SlimX against corpus/cache, and render SLIMX_CORPUS directories you trust (colon-separated)"
  task :check do
    report = ["--report", ENV["REPORT"]] if ENV["REPORT"]
    ruby "-Ilib", "script/corpus_check.rb", *report, File.join("corpus", "cache") if File.directory?(File.join("corpus", "cache"))
    trusted_directories = ENV.fetch("SLIMX_CORPUS", "").split(":").reject(&:empty?)
    ruby "-Ilib", "script/corpus_check.rb", "--render", *trusted_directories if trusted_directories.any?
  end
end
