# SuperSlim

A Slim 5 template engine rewritten without Temple: the HTML Slim renders with `format: :html, sort_attrs: false`,
byte for byte, plus a formatter (`super-slim fmt`) and a linter (`super-slim lint`). One parser
(`lib/super_slim/parser.rb`) feeds the compiler, the formatter and the linter. A Next Gen Gems gem, by Level UP
Solutions, and the model the organization's other gems copy.

## Compatibility

- Every maintained Ruby and Rails (https://endoflife.date), nothing older: the oldest Ruby sets
  `required_ruby_version` and `TargetRubyVersion`. Today Ruby 3.3, 3.4, 4.0 and Rails 8.0, 8.1. A version leaves
  in the release after its end of life.
- Rails is optional (railtie, `RailsHandler`). `Gemfile` takes the newest Rails, `gemfiles/rails_8_0.gemfile`
  the oldest maintained one.
- CI (`.github/workflows/ci.yml`) runs RuboCop, the tests on each maintained Ruby, and `ruby-head`, and the
  corpus check; not on drafts. No macOS job: we run the tests on Macs.

## Commands

```sh
bundle exec rake test                        # test:super_slim, then test:slim_suite (Slim's own suites against SuperSlim)
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test
bundle exec rubocop                          # Standard's rules and every rubocop-performance cop
UPDATE_GOLDEN=1 bundle exec rake test:super_slim  # rewrites test/golden: review the diff
FUZZ_SEED=42 FUZZ_CASES=20000 bundle exec ruby -Ilib -Itest test/fuzz_test.rb
bundle exec rake corpus:fetch corpus:check   # public templates of corpus/manifest.yml
bundle exec rake corpus:diff BASE=main       # what a change does to the corpus: compiled Ruby, format, lint
bundle exec ruby --yjit -Ilib bench/render.rb
BENCH_LOCK=path/to/.bench.lock bundle exec rake bench  # rewrites docs/benchmarks.json; the lock serializes benchmarks
bundle exec rake docs                        # rewrites the linter rules of docs/tools.html
```

## Traps

- Ruby 3.3: a bare `it` in a block is a method call there, write `_1`; `StringScanner#peek_byte` needs
  strscan 3.1.1 or later, hence the gemspec dependency.
- `test:slim_suite` runs in a process of its own: Slim's test helper defines and removes `String#html_safe?`.
- Downloaded corpus templates are never rendered, as rendering runs their Ruby: only the `SUPER_SLIM_CORPUS`
  directories you trust are.
- A refactoring must leave the compiled Ruby unchanged: `bench/compiled_digests.rb` proves it on a corpus.
- `.claude/hooks/rubocop.sh` autocorrects each Ruby file after an edit (except `Lint/UselessAssignment`) and
  hands back what it cannot fix. `Style/RedundantRegexpEscape`'s autocorrect turns `#\{` in a regexp into an
  interpolation: read its diffs.
- A hot-path change is measured with and without YJIT; a Performance cop the numbers contradict is disabled on
  its line, with the reason.
- Test and bench data stay anonymized (`alice`, `Post`, `example.com`).

## Code style

Follow `STYLE.md` (naming, method size, comments, dead code): what RuboCop can't settle.

## Changelog and releases

- Never edit `CHANGELOG.md` in a PR: any two PRs adding a line there conflict. The changelog is written when
  releasing, from the PRs merged since the last tag; a PR title says what changes for users.
- A draft runs no CI, so it never turns green. Confident in the change: open the pull request ready for review,
  auto-merge on. Not yet: a draft, then `gh pr ready` when it needs the CI.
- To release, read every PR merged since the last tag (`git log --first-parent --oneline <tag>..origin/main`,
  squash merges end in `(#n)`, then `gh pr view n`), and write the release under `## [Unreleased]` without
  committing it: a one-sentence lede, then **Breaking**, **New**, **Faster** (measured, with and without YJIT)
  and **Fixed**, only those with entries. One entry per change users can see, written for them: several PRs may
  make one, CI, refactoring, docs and tests make none. Show it to the user, then `bin/release` commits it with
  the version. No version heading, date or link by hand: `bin/release` writes them.
- `main` takes no direct push, ours included: every change, a release too, goes through a pull request that merges
  itself once the required CI checks are green (`gh pr merge --auto --squash`).
- `bin/release patch|minor|major` cuts a release from a green, up-to-date `main` through such a pull request, then
  tags its merge commit (README, Releasing), and `.github/workflows/release.yml` publishes it. Both are the same in
  every next-gen-gems gem: change them in all four at once.
- RubyGems trusts the Release workflow (trusted publishing): never `gem push` from a machine.

## Pull requests and issues

- Title: the change as a user sees it (an issue: the finding), in plain words, under 70 characters.
- Body, no headings: two short paragraphs, the problem then the change (an issue: what to do); 3 to 5 bullets,
  each a **bold 2–4 word lead-in** and two lines at most (decisions, divergences, what is left out); the proof
  (reproduction, tests, fuzz seeds, benchmarks) folded in one `<details>`. Nothing the diff or the CI says.
