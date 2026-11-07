# frozen_string_literal: true

namespace :corpus do
  desc "Compare a base revision (BASE, origin/main by default) with the working tree over corpus/cache and SUPER_SLIM_CORPUS; FORMATTING_CHANGES=1 lets formatting change"
  task :diff do
    options = [*(["--base", ENV["BASE"]] if ENV["BASE"]), *("--formatting-changes" if ENV["FORMATTING_CHANGES"])]
    ruby "script/corpus_diff.rb", *options, File.join("corpus", "cache") if File.directory?(File.join("corpus", "cache"))
    trusted_directories = ENV.fetch("SUPER_SLIM_CORPUS", "").split(":").reject(&:empty?)
    ruby "script/corpus_diff.rb", *options, "--render", *trusted_directories if trusted_directories.any?
  end
end
