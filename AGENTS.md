# SuperSlim

A Slim 5 template engine without Temple: it renders the HTML Slim renders with `format: :html, sort_attrs: false`,
byte for byte, plus a formatter (`super-slim format`) and a linter (`super-slim lint`). One parser,
`lib/super_slim/parser.rb`, feeds all three.

`README.md` covers usage, `STYLE.md` code style, `CONTRIBUTING.md` contributions; this file adds what they leave out.

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

CI also runs `ruby-head` and the corpus job.

## Traps

- Rails is optional: it stays out of the gemspec.
- Ruby 3.3's strscan lacks `StringScanner#peek_byte`, hence strscan 3.1.1+ in the gemspec.
- Ruby 3.3 ships Prism 0.19, but the Gemfile resolves Prism 1.x through RuboCop: only CI's `prism` job formats and
  lints with 0.19 (`BUNDLE_GEMFILE=gemfiles/prism_0_19.gemfile bundle exec rake test:prism`).
- `test:slim_suite` runs in its own process: Slim's test helper defines and removes `String#html_safe?`.
- Never render downloaded corpus templates, it runs their Ruby: only the `SUPER_SLIM_CORPUS` directories you trust.
- A refactoring leaves the compiled Ruby unchanged: `bench/compiled_digests.rb` proves it on a corpus.
- A pull request that changes `super-slim format`'s output on purpose needs the `formatting change` label, or the
  corpus job fails.
- `Style/RedundantRegexpEscape`'s autocorrect turns `#\{` in a regexp into an interpolation: read the hook's changes.
- Before a release, refresh the site's numbers on a quiet machine
  (`SUPER_SLIM_CORPUS=path/to/app/views bundle exec rake bench`), merged in their own pull request.

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
  whatever the conversation's language.
- No AI attribution in anything people read; commits flag AI help with `Assisted-by`, never `Co-Authored-By`.

## Pull requests and issues

- `main` takes no direct push: every change, releases included, goes through a pull request that merges itself once
  CI is green (`gh pr merge --auto --squash`).
- Drafts run no CI. Confident: open it ready, auto-merge on. Not yet: a draft, then `gh pr ready` when it needs CI.
- Never edit `CHANGELOG.md` in a pull request, they would all conflict: it is written at release time.
- Title: the change as a user sees it (an issue: the finding), in plain words, under 70 characters.
- Body, no headings: two short paragraphs, the problem then the change (an issue: what to do); 3 to 5 bullets, each
  opening with a **bold 2–4 word lead-in**; the proof (reproduction, tests, benchmarks) folded in one `<details>`.
  Nothing the diff or CI already says.
- Never hard-wrap a pull request, an issue or a comment: GitHub renders every line break. One line per paragraph and
  per bullet.

## Releases

The user is needed twice: a working git signing key (the tag is signed) and one click approving the `release`
environment on GitHub.

1. Another session may have just released: `git fetch --tags origin`, and `gh pr list --search "head:release/"`
   must be empty. Unreleased changes: `git log --first-parent --oneline $(git describe --tags --abbrev=0 origin/main)..origin/main`,
   then `gh pr view <n>` for each.
2. Write the release under `## [Unreleased]` in `CHANGELOG.md`, uncommitted: a one-sentence lede, then **Breaking**,
   **New**, **Faster** (measured), **Fixed**, only those with entries. One entry per change users see, written for
   them; CI, refactoring, docs and tests get none. No version, date or link: `bin/release` adds them.
3. Show it to the user, wait for their go. From `main` level with `origin/main`, `CHANGELOG.md` its only change:
   `bin/release minor --dry-run`, then `bin/release minor --yes` (or `patch`, `major`). It opens `release/vX.Y.Z`,
   waits for it to merge itself, pushes the signed tag. Signing fails: the user fixes it, never an unsigned tag.
   Interrupted after the merge: `bin/release --tag X.Y.Z`.
4. The tag runs `release.yml`, which waits for the user to approve the `release` environment, then publishes to
   RubyGems and GitHub. Open that run in their browser, where they click Review deployments, `release`, Approve:
   `gh run view --web $(gh run list --workflow release.yml --branch vX.Y.Z --json databaseId -q '.[0].databaseId')`,
   once the run exists: it starts a few seconds after the tag, and without `--branch` the previous release's run
   opens.
   Then check RubyGems.

RubyGems trusts only that workflow: never `gem push`, except a new gem name's first version. `bin/release` and
`release.yml` are identical in all four gems.
