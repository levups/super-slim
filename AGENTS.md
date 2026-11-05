# SuperSlim

A Slim 5 template engine rewritten without Temple. It renders the HTML Slim renders with
`format: :html, sort_attrs: false`, byte for byte, and adds a formatter (`super-slim format`) and a linter
(`super-slim lint`). One parser, `lib/super_slim/parser.rb`, feeds all three.

Read `README.md` for usage, `STYLE.md` for code style and `CONTRIBUTING.md` for contributions; this file only
adds what they leave out.

## Commands

```sh
bundle exec rake test                                            # our tests, then Slim's own suites against SuperSlim
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test  # the oldest maintained Rails
bundle exec rubocop
UPDATE_GOLDEN=1 bundle exec rake test:super_slim                 # rewrites test/golden: review the diff
FUZZ_SEED=42 FUZZ_CASES=20000 bundle exec ruby -Ilib -Itest test/fuzz_test.rb
bundle exec rake corpus:fetch corpus:check                       # public templates pinned in corpus/manifest.yml
bundle exec rake corpus:diff BASE=main                           # what a change does to the corpus
bundle exec ruby --yjit -Ilib bench/render.rb
BENCH_LOCK=path/to/.bench.lock bundle exec rake bench            # rewrites docs/benchmarks.json, waits for the lock
bundle exec rake docs                                            # rewrites the linter rules in docs/tools.html
```

CI also runs `ruby-head` and the corpus check.

## Traps

- Rails is optional: it stays out of the gemspec.
- Ruby 3.3's strscan has no `StringScanner#peek_byte`: that is why the gemspec requires strscan 3.1.1 or later.
- `test:slim_suite` runs in a process of its own, because Slim's test helper defines and removes
  `String#html_safe?`.
- Never render downloaded corpus templates: rendering runs their Ruby. Only the `SUPER_SLIM_CORPUS` directories you
  trust are rendered.
- A refactoring leaves the compiled Ruby unchanged: `bench/compiled_digests.rb` proves it on a corpus.
- The autocorrect of `Style/RedundantRegexpEscape` turns `#\{` in a regexp into an interpolation: read the hook's
  changes.
- Before a release, refresh the site's numbers on a quiet machine
  (`SUPER_SLIM_CORPUS=path/to/app/views bundle exec rake bench`) and merge them in their own pull request.

## Rules for all our gems

This section and the next two read the same in super-slim, gamba, crumbly and agentry: change all four together.

- Every maintained Ruby and Rails (https://endoflife.date), nothing older. The oldest sets `required_ruby_version`,
  `TargetRubyVersion` and the Rails floor, and leaves in the release after its end of life.
- CI runs RuboCop and the tests on each maintained Ruby. No macOS job: we test on our Macs.
- `.claude/hooks/rubocop.sh` autocorrects each Ruby file you edit.
- Measure performance without JIT and with YJIT. A Performance cop the numbers contradict is disabled on its line,
  with the reason. A pure performance change pins no internals in tests.
- Test and bench data are anonymized: `alice`, `Post`, `example.com`.
- Everything in the repository is in English (code, comments, commits, pull requests, issues, reviews, replies),
  whatever the language of the conversation.
- No AI attribution in anything people read.

## Pull requests and issues

- `main` takes no direct push. Every change, releases included, goes through a pull request that merges itself
  once CI is green: `gh pr merge --auto --squash`.
- Drafts run no CI. Confident in the change? Open it ready for review, auto-merge on. Not yet? Open a draft, then
  `gh pr ready` when it needs CI.
- Never edit `CHANGELOG.md` in a pull request: they would all conflict. It is written at release time.
- Title: the change as a user sees it (for an issue, the finding), in plain words, under 70 characters.
- Body, no headings: two short paragraphs, the problem then the change (for an issue, what to do); 3 to 5 bullets,
  each opening with a **bold 2–4 word lead-in**; the proof (reproduction, tests, benchmarks) folded in one
  `<details>`. Nothing the diff or CI already says.
- Never hard-wrap a pull request, an issue or a comment: GitHub renders every line break. One line per paragraph
  and per bullet.

## Releases

1. List the pull requests merged since the last tag: `git log --first-parent --oneline <tag>..origin/main`, then
   `gh pr view <n>` for each.
2. Write the release under `## [Unreleased]` in `CHANGELOG.md`, uncommitted: a one-sentence lede, then
   **Breaking**, **New**, **Faster** (measured) and **Fixed**, only those with entries. One entry per change users
   can see, written for them; CI, refactoring, docs and tests get none. No version, date or link: `bin/release`
   adds them.
3. Show it to the user. Then `bin/release patch|minor|major` (try `--dry-run` first) commits it through a pull
   request, waits for the merge and tags it; the tag runs `.github/workflows/release.yml`, which publishes the gem.

RubyGems trusts only that workflow: never `gem push` from a machine, except the very first version of a new gem
name. `bin/release` and `release.yml` are the same in all four gems.
