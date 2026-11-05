# frozen_string_literal: true

namespace :corpus do
  desc "Compare a base revision (BASE, origin/main by default) with the working tree over corpus/cache and SUPER_SLIM_CORPUS"
  task :diff do
    base = ["--base", ENV["BASE"]] if ENV["BASE"]
    ruby "script/corpus_diff.rb", *base, File.join("corpus", "cache") if File.directory?(File.join("corpus", "cache"))
    trusted_directories = ENV.fetch("SUPER_SLIM_CORPUS", "").split(":").reject(&:empty?)
    ruby "script/corpus_diff.rb", *base, "--render", *trusted_directories if trusted_directories.any?
  end
end
