# SlimX

A Slim template engine rewritten from scratch: no Temple, no filter pipeline, a single-pass compiler and a
render-time runtime of a few methods. Templates written for [Slim](https://github.com/slim-template/slim) 5
render byte for byte the same, faster, with fewer allocations.

https://next-gen-gems.github.io/slimx/

## Installation

```ruby
# Gemfile
gem "slimx" # instead of slim-rails
```

## Usage

Rails picks it up through its railtie. Outside Rails, `require "slimx/tilt"` registers it with Tilt
(Sinatra, Hanami, Roda…), and `SlimX.compile(source)` returns the Ruby code.

## What SlimX renders

HTML5, with attributes in the order you write them — what Slim renders with
`format: :html, sort_attrs: false`. Templates whose format is XML (`.xml`, `.rss`, `.atom`) render as XML
(`<link />`, `doctype xml`) from their format alone.

The whole Slim 5 grammar is supported: tags and `#id`/`.class` shortcuts, custom shortcuts, attributes with
any delimiter, boolean attributes, `*splat`, `data`/`aria` hashes, `class` merging, `<`/`>` whitespace
markers, `|` and `'` text, inline HTML, `/` and `/!` comments, `-` control code, `=`/`==` output, `#{}` and
`#{{}}` interpolation, `doctype`, and the `ruby:`, `javascript:`, `css:` and `markdown:` (through
[Markly](https://github.com/ioquatix/markly)) embedded engines.

## Tailwind class names

Slim cuts `.rounded-b-[3px]` at the bracket, and refuses `.lg:[&:nth-child(3)]:hover:underline`. Turn on
`tailwind_classes` and the `.` shortcut takes any Tailwind class name:

```slim
.p-1.rounded-b-[3px].lg:[&:nth-child(3)]:hover:underline
.font-['Open_Sans'].bg-(--brand).mx-0.5.w-1/2.!font-bold.@lg:flex
ul.*:p-2
```

```ruby
SlimX.tailwind_classes = true # config/initializers/slimx.rb, or tailwind_classes: true per compile
```

```yaml
# .slimx.yml, for slimx lint and slimx fmt
tailwind_classes: true
```

Attribute lists keep their meaning: Tailwind never puts a bracket right after a letter or a digit, so
`a.btn[href="/"]` is still a link with a class and an `href`. A colon followed by a space still nests a tag
(`li.item: a`), and a final `/` still closes one. What changes is what Slim mangles: it renders `.size-2.5` as
`class="size-2 5"`, the option as `class="size-2.5"`. On 7,505 templates from 31 apps, 16 compile differently
with the option, all of them Tailwind classes Slim breaks. It stays off by default all the same, so that
turning SlimX on changes nothing.

The option only changes how templates are read: compiling 1,408 templates takes the same time (+0.5%, within
noise), and the compiled Ruby, so the time it takes to render, is the same.

## What SlimX leaves out

Each fails at compile time with a clear error instead of being silently ignored:

- the XHTML format, `sort_attrs`, `attr_quote`, `pretty`, `js_wrapper` and every Temple option;
- the `coffee:`, `sass:`, `scss:`, `less:`, `erb:`, `builder:`, `textile:`, `rdoc:`, `asciidoc:` and wiki
  engines, and `/[if IE]` conditional comments;
- the `logic_less`, `translator`, `include` and `smart` plugins, and lambda shortcuts.

They can come back if people ask, as long as they cost nothing at render time.

## Migrating from Slim

Slim's defaults are `format: :xhtml` and `sort_attrs: true`. If you never changed them, first switch Slim
to `format: :html, sort_attrs: false` and check your test suite: that is the output SlimX gives. Then swap
`slim-rails` for `slimx`, and drop any `Slim::Engine.set_options`/`with_options` call.

## Formatter, strict mode and linter

One parser serves the compiler, the formatter and the linter, so all three read templates the same way.

`slimx fmt [--check] [PATH…]` rewrites templates in their canonical layout: two spaces per level, `- code`,
`= output` and `p = output` spacing, no redundant `div`, no trailing whitespace, single blank lines, one final
newline. Text blocks move as a whole, so the whitespace they render stays put — and before writing anything,
the formatter compiles both versions and refuses if the Ruby differs. Formatting cannot change a page.

Strict mode (`SlimX.strict = true`, or `strict: true` per compile) refuses any template that `slimx fmt` would
change, pointing at the first line and what it should be: `gofmt` discipline at compile time.

`slimx lint [PATH…]` reads `.slimx.yml` and checks, in about half the time slim-lint takes:

| Rule | From | Default |
|---|---|---|
| Indentation, Tab, TrailingWhitespace, EmptyLines, TrailingBlankLines, ControlStatementSpacing, RedundantDiv | slim-lint, fixed by `slimx fmt` | on |
| LineLength (`max: 120`), CommentControlStatement, EmptyControlStatement, ConsecutiveControlStatements (`max: 2`), TagCase | slim-lint | on |
| InstanceVariables (in partials) | haml-lint, Rails conventions | on |
| StrictLocals (partials declare `/# locals:`) | Rails 7.1 strict locals | off |
| DuplicateId, ImageAlt, IframeTitle, AnchorHref, NestedLinks, PositiveTabindex, BooleanAttributeValue, AriaRole, AriaAttribute | Herb, eslint-plugin-jsx-a11y | on |
| ButtonType, InlineStyles | eslint-plugin-react, haml-lint | off |
| DeprecatedClasses (`classes: {old: new}`) | erb_lint | on, empty |
| UnnecessaryInterpolation, UnnecessaryStringOutput | haml-lint | on |
| Zwsp (invisible characters) | slim-lint | on |

```yaml
# .slimx.yml
linters:
  LineLength:
    max: 150
  ButtonType:
    enabled: true
  DeprecatedClasses:
    classes:
      text-muted: text-body-secondary
```

## How it is tested

- Slim's own test suite and its literate specification (`TESTS.md`) run against SlimX: every template renders
  through Slim and SlimX, and both outputs must match.
- A seeded fuzzer generates thousands of random templates from the grammar and compares both engines; CI adds
  10,000 from a new seed on every run.
- Golden snapshots (`test/golden`) hold the rendered HTML, compiled Ruby, formatting and lint offenses of
  templates covering the grammar, its errors and Tailwind class names: `UPDATE_GOLDEN=1` rewrites them.
- `bench/compiled_digests.rb` proves a refactoring leaves the compiled Ruby of a whole corpus unchanged.

Real templates come from 30 public apps pinned in `corpus/manifest.yml`: `rake corpus:fetch` downloads only
their `.slim` files into the ignored `corpus/cache`, `rake corpus:check` compiles, formats and lints each one
against Slim, and `rake corpus:diff BASE=rev` reports what changes between a revision and the working tree:
compiled Ruby, formatting, lint offenses. Downloaded templates are never rendered, as rendering runs their
Ruby; directories you trust, such as your own app, render too when passed in `SLIMX_CORPUS`.

## Benchmarks

`bench/compare.rb` renders the same blog page with SlimX, Slim, Haml, Erubi and Herb, checks that they all
produce the same HTML, and writes compile and render speed and allocations to `docs/benchmarks.json`, which
the website reads. Run it before each release, on a quiet machine:

```sh
bundle exec rake bench                                  # YJIT, 5 seconds per measurement
SLIMX_CORPUS=path/to/app/views bundle exec rake bench   # adds the compile time of a whole app against Slim
BENCH_LOCK=path/to/.bench.lock bundle exec rake bench   # waits for other benchmarks holding that lock
```

With `corpus/cache` fetched, it also times the open-source corpus, and `slimx lint` and `fmt` there against
slim-lint when it is installed. `bundle exec rake docs` rewrites the linter rules on the website
(`docs/tools.html`), after checking every example against the linter.

## Development

```sh
bundle install
bundle exec rake test                                # SlimX's tests, then Slim's own suites
BUNDLE_GEMFILE=gemfiles/rails_8_0.gemfile bundle exec rake test  # the same on Rails 8.0
bundle exec rubocop
FUZZ_SEED=42 FUZZ_CASES=20000 bundle exec ruby -Ilib test/fuzz_test.rb
bundle exec ruby -Ilib bench/corpus.rb path/to/app   # compile time and allocations against Slim
bundle exec ruby --yjit -Ilib bench/render.rb        # render speed and allocations against Slim
```

### Releasing

Pull requests leave `CHANGELOG.md` alone: a release starts by writing its notes under `## [Unreleased]`, from the
pull requests merged since the last tag, without committing them. Refresh the website's numbers on a quiet machine
(`SLIMX_CORPUS=path/to/app/views bundle exec rake bench`) and merge them through a pull request, then, from an
up-to-date `main` whose CI is green:

```sh
bin/release minor --dry-run   # the notes and the changes, nothing written
bin/release minor             # or patch, major, or an exact version such as 1.2.0
```

`main` takes no direct push, so `bin/release` dates the Unreleased section and bumps the version on a branch
`release/vX.Y.Z`, opens its pull request, which merges itself once CI is green, and waits for it. It then pushes a
signed tag `vX.Y.Z` on the merge commit (`bin/release --tag X.Y.Z` does it if you stopped waiting). The tag starts
the Release workflow, which publishes the gem to RubyGems through trusted publishing and creates the GitHub release
with the version's notes and the `.gem`.

## License

MIT, by Level UP Solutions, part of [Next Gen Gems](https://github.com/next-gen-gems). The parser follows the
grammar and parsing algorithm of [Slim](https://github.com/slim-template/slim), by the Slim Team (MIT).
