# frozen_string_literal: true

# Prints, as JSON keyed by path, what the SuperSlim on the load path makes of every .slim file: compiled Ruby for Tilt
# and Rails (digests, or the error), formatted source (digest, or the error) and lint offenses. script/corpus_diff.rb
# runs it once per revision and compares.
#   ruby -I<revision>/lib script/corpus_snapshot.rb [--render | --formatted] DIRECTORY_OR_FILE...
#
# --render adds the HTML each template renders against the stub of script/corpus_support.rb. Rendering runs the
# template's Ruby: only for directories you trust. --formatted prints, for the templates given, only their formatted
# source, or the error, for script/corpus_diff.rb to show.
require "digest"
require "json"
require "super_slim"
require "super_slim/linter"
require_relative "corpus_support"
# From this checkout, not the revision on the load path, which may predate it: it depends on nothing.
require_relative "../lib/super_slim/parallel"

render = !ARGV.delete("--render").nil?
formatted = !ARGV.delete("--formatted").nil?
if render
  require "active_support/all"
  Corpus.stub_missing_constants!
end

linter = SuperSlim::Linter.new
digest_or_error = ->(&block) { Corpus.compile_error_or { Digest::SHA256.hexdigest(block.call) } }

paths = ARGV.flat_map { File.file?(_1) ? [File.expand_path(_1)] : Dir[File.join(File.expand_path(_1), "**/*.slim")] }.sort
if formatted
  puts JSON.generate(paths.to_h { |path| [path, Corpus.compile_error_or { SuperSlim::Formatter.new.call(File.read(path)) }] })
  exit
end

snapshot = SuperSlim::Parallel.map(paths, minimum_per_process: 200) do |path|
  source = File.read(path)
  format = Corpus.format_of(path)
  tilt_code = Corpus.compile_error_or { SuperSlim.compile(source, file: path, format:) }
  record = {
    "tilt" => tilt_code.start_with?("error:") ? tilt_code : Digest::SHA256.hexdigest(tilt_code),
    "rails" => digest_or_error.call { SuperSlim.compile(source, file: path, format:, rails: true) },
    "fmt" => digest_or_error.call { SuperSlim::Formatter.new.call(source) },
    "lint" => Corpus.outcome { linter.call(path, source).map { |offense| "#{offense.rule}:#{offense.lineno}: #{offense.message}" } }
  }
  record["html"] = tilt_code.start_with?("error:") ? tilt_code : Corpus.render(tilt_code, path, source) if render
  [path, record]
end.to_h

puts JSON.generate(snapshot)
