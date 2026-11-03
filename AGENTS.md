# SlimX

A Slim 5 template engine rewritten without Temple: the HTML Slim renders with `format: :html, sort_attrs: false`,
byte for byte, plus a formatter (`slimx fmt`), a strict mode and a linter (`slimx lint`). One parser
(`lib/slimx/parser.rb`) feeds the compiler, the formatter and the linter. A Next Gen Gems gem, by Level UP
Solutions, and the model the organization's other gems copy.

## Compatibility

- Every maintained Ruby and Rails (https://endoflife.date), nothing older: the oldest Ruby sets
  `required_ruby_version` and `TargetRubyVersion`. Today Ruby 3.3, 3.4, 4.0 and Rails 8.0, 8.1. A version leaves
  in the release after its end of life.
- Rails is optional (railtie, `RailsHandler`). `Gemfile` takes the newest Rails, `gemfiles/rails_8_0.gemfile`
  the oldest maintained one.
- CI (`.github/workflows/ci.yml`) calls next-gen-gems/.github's shared `gem-ci.yml@main` (RuboCop, each Ruby
  with each Gemfile, `ruby-head`, macOS) and runs the corpus job of its own.

## Commands

```sh
bundle exec rake test                        # test:slimx, then test:slim_suite (Slim's own suites against SlimX)
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test
bundle exec rubocop                          # Standard's rules and every rubocop-performance cop
UPDATE_GOLDEN=1 bundle exec rake test:slimx  # rewrites test/golden: review the diff
FUZZ_SEED=42 FUZZ_CASES=20000 bundle exec ruby -Ilib -Itest test/fuzz_test.rb
bundle exec rake corpus:fetch corpus:check   # public templates of corpus/manifest.yml
bundle exec rake corpus:diff BASE=main       # what a change does to the corpus: compiled Ruby, format, lint
bundle exec ruby --yjit -Ilib bench/render.rb
BENCH_LOCK=~/github/oss/benchmarks/.bench.lock bundle exec rake bench  # rewrites docs/benchmarks.json
bundle exec rake docs                        # rewrites the linter rules of docs/tools.html
```

## Traps

- Ruby 3.3: a bare `it` in a block is a method call there, write `_1`; `StringScanner#peek_byte` needs
  strscan 3.1.1 or later, hence the gemspec dependency.
- `test:slim_suite` runs in a process of its own: Slim's test helper defines and removes `String#html_safe?`.
- Downloaded corpus templates are never rendered, as rendering runs their Ruby: only the `SLIMX_CORPUS`
  directories you trust are.
- A refactoring must leave the compiled Ruby unchanged: `bench/compiled_digests.rb` proves it on a corpus.
- `.claude/hooks/rubocop.sh` autocorrects each Ruby file after an edit (except `Lint/UselessAssignment`) and
  hands back what it cannot fix. `Style/RedundantRegexpEscape`'s autocorrect turns `#\{` in a regexp into an
  interpolation: read its diffs.
- A hot-path change is measured with and without YJIT; a Performance cop the numbers contradict is disabled on
  its line, with the reason.
- Test and bench data stay anonymized (`alice`, `Post`, `example.com`).
- User-facing changes go in `CHANGELOG.md`; the release steps end `README.md`.
