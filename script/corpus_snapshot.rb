# frozen_string_literal: true

# Prints, as JSON keyed by path, what the SlimX on the load path makes of every .slim file: compiled Ruby for Tilt
# and Rails (digests, or the error), formatted source (digest, or the error) and lint offenses. script/corpus_diff.rb
# runs it once per revision and compares.
#   ruby -I<revision>/lib script/corpus_snapshot.rb [--render] DIRECTORY...
#
# --render adds the HTML each template renders against the stub of script/corpus_support.rb. Rendering runs the
# template's Ruby: only for directories you trust.
require "digest"
require "json"
require "slimx"
require "slimx/linter"
require_relative "corpus_support"
# From this checkout, not the revision on the load path, which may predate it: it depends on nothing.
require_relative "../lib/slimx/parallel"

render = !ARGV.delete("--render").nil?
if render
  require "active_support/all"
  Corpus.stub_missing_constants!
end

linter = SlimX::Linter.new
digest_or_error = ->(&block) { Corpus.compile_error_or { Digest::SHA256.hexdigest(block.call) } }

paths = ARGV.flat_map { Dir[File.join(File.expand_path(_1), "**/*.slim")] }.sort
snapshot = SlimX::Parallel.map(paths, minimum_per_process: 200) do |path|
  source = File.read(path)
  format = Corpus.format_of(path)
  tilt_code = Corpus.compile_error_or { SlimX.compile(source, file: path, format:, strict: false) }
  record = {
    "tilt" => tilt_code.start_with?("error:") ? tilt_code : Digest::SHA256.hexdigest(tilt_code),
    "rails" => digest_or_error.call { SlimX.compile(source, file: path, format:, rails: true, strict: false) },
    "fmt" => digest_or_error.call { SlimX::Formatter.new.call(source) },
    "lint" => Corpus.outcome { linter.call(path, source).map { |offense| "#{offense.rule}:#{offense.lineno}: #{offense.message}" } }
  }
  record["html"] = tilt_code.start_with?("error:") ? tilt_code : Corpus.render(tilt_code, path, source) if render
  [path, record]
end.to_h

puts JSON.generate(snapshot)
