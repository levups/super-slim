# frozen_string_literal: true

# Prints one digest of SuperSlim's compiled Ruby per template, to prove a refactoring leaves every output unchanged:
#   diff <(git stash-free checkout of the baseline …) <(ruby -Ilib bench/compiled_digests.rb path/to/app)
require "digest"
require "super_slim"

Dir[File.join(ARGV.fetch(0), "**/*.slim")].sort.each do |path|
  code = begin
    SuperSlim.compile(File.read(path), file: path, rails: true, html_safe: true)
  rescue SuperSlim::Error => exception
    exception.message
  end
  puts "#{Digest::SHA256.hexdigest(code)[0, 16]} #{path}"
end
