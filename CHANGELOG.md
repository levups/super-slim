# Changelog

## [Unreleased]

## [3.4.1] — 2026-11-07

One fix: `super-slim format` no longer writes `-` lines that `super-slim lint` flags.

**Fixed**
- `super-slim format` no longer turns a one- or two-line `ruby:` block into `-` lines that make three in a row with
  the ones around it, which ConsecutiveControlStatements then flagged and a format-then-lint commit hook refused.
  `#{}` in a string no longer keeps a line out of a `ruby:` block.

## [3.4.0] — 2026-11-07

One layout for inline tags, short children, `ruby:` blocks and negated conditions.

**New**
- `super-slim format` puts tags nested inline after a colon (`tr: td = total`) one per line, their children going as
  many levels deeper. A line whose text goes on below keeps its inline tags.
- `-` lines and `ruby:` blocks next to each other at one depth make one run of code: three lines or more go in a
  `ruby:` block, as the ConsecutiveControlStatements rule asks, and fewer on `-` lines. Only lines of Ruby complete on
  their own move.
- With `max_line_length`, a tag whose only child is one `=` output or one line of `|` text takes it on its own line
  when both fit: `td = total`, `p Hello`. Text that could read as an attribute stays below.
- `- if !condition` becomes `- unless condition` when the `!` covers the whole condition and no `else` follows. The
  formatter's check takes the two for the same code.
- Lines under `/ super-slim:format off` stay out of these rules.

## [3.3.0] — 2026-11-07

Formatted templates that Slim and Brakeman read, lines and rules you can opt out of, and a formatter about 30% faster.

**New**
- `/ super-slim:format off` keeps the lines after it as written, up to `/ super-slim:format on` or the end of their
  block, and `/ super-slim:disable Rule, OtherRule` silences rules for the next tag or line of code. An unknown rule
  name, or a directive with no line after it, is reported.
- The `SlimSyntax` lint rule, on by default, flags what Slim, and so Brakeman, can't read: code continued after an
  opening bracket, and a comment after code.
- The `AriaBooleanValue` lint rule, on by default, flags `aria-*=true`, which renders without a value, and
  `aria-*=false`, which Slim leaves out.
- `super-slim format` removes a blank line at the start of a block, sets a partial's first-line `/# locals:`
  signature apart with a blank line, and writes the `do` that Slim adds to a line of code whose children render
  something.

**Faster**
- `super-slim format` is about 30% faster: it compares the compiled Ruby as text before parsing it, and reads each
  template once.

**Fixed**
- With `max_line_length`, `super-slim format` spreads a long call one argument per line, each line but the last
  ending with a comma, instead of between brackets that close on a line of their own. Slim only continues code after
  a comma or a backslash, so since 3.2.0 Brakeman could check nothing in a wrapped template. Formatting again
  repairs the templates already written, a tag's output after its attributes included. A first argument too long to
  follow its call, or the brackets or the `do` that close the last one, go to the next line after a backslash.
- Code spread by hand with a comment inside stays as written, instead of keeping the formatter from wrapping
  anything else in its file.

## [3.2.2] — 2026-11-06

`super-slim format` no longer joins code spread by hand into lines past `max_line_length`.

**Fixed**
- With `max_line_length`, an argument that still passes the limit once its call is spread one argument per line
  spreads its own elements or arguments in turn, an array before `.join` included, instead of coming back on one
  long line. Code spread by hand, such as a string continued with a backslash, keeps its layout whenever the
  formatted one would hold a longer line.

## [3.2.1] — 2026-11-06

A comment after Ruby code no longer breaks the template.

**Fixed**
- A comment that ends a line of Ruby code, as in
  `= render CardComponent.new(post:) # rubocop:disable Some/Cop -- reason`,
  no longer makes the template a syntax error: it is left out of the
  compiled Ruby, after `=`, `==` and `-` alike, so a RuboCop directive can
  sit on the line it is about. Slim refuses these lines.

## [3.2.0] — 2026-11-06

One layout per line and per tag in `super-slim format`, cache digests that follow Slim partials, and a faster lint.

**New**
- With `max_line_length`, `super-slim format` gives each line one layout: Ruby code spread over several lines is
  joined back when it fits, and a longer call spreads its arguments one per line between parentheses, each followed
  by a comma. Code spread by hand stays as it is when this layout would pass the limit.
- A tag's attributes stand without delimiters when they fit on its line, and one per line inside
  `attribute_delimiters` when they don't. A literal `id` or `class` becomes a shortcut, a repeated class shortcut
  goes, and attributes follow one order, from `id` and `class` to `aria-*` and `role`. The formatter takes attribute
  values to have no side effects.

**Faster**
- `super-slim lint` is 11 to 22% faster, and finding templates from an app's root skips `node_modules` and `tmp`:
  twice as fast.

**Fixed**
- The digest of a `cache` block in a Slim view now follows the partials it renders, as in ERB: a changed partial
  no longer serves a stale fragment. A partial whose name is computed needs `/# Template Dependency: path`. Each
  such fragment is rebuilt once after the upgrade, and Rails 8.0 processes without eager loading now load Prism
  with Action View.
- The RuboCop plugin's autocorrect works on templates with CRLF line endings, and `super-slim format` keeps the
  spaces a line renders.

## [3.1.1] — 2026-11-06

Two ways for data to inject markup closed, hostile templates read in linear time, and Prism kept out of rendering.

**Fixed**
- Loading SuperSlim no longer loads Prism, which only `super-slim format` needs: since 3.1.0, every process that
  loaded the gem, each Puma worker included, paid Prism's load time and about 7 MB.
- A tab, line feed, form feed or carriage return in a `*splat` or `data`/`aria` key raises
  `InvalidAttributeNameError` instead of ending the attribute name, and `*{tag: …}` raises the new
  `InvalidTagNameError` when its value is not a tag name: both let data inject markup, as in Slim 5.2.2. No valid
  page changes.
- Hostile templates no longer hang or crash the compiler, `lint`, `format` or the RuboCop plugin: nested `#{`, long
  continued code and deep nesting are read in linear time, and tags nested more than 500 levels deep are a syntax
  error.
- On a hostile checkout, the CLI skips symlinks, FIFOs and devices, writes atomically and escapes control
  characters in what it prints; a malformed `.super-slim.yml` is a usage error that names the setting.
- `super-slim format` refuses a wrap of a template that doesn't compile and a move of `__LINE__`, and its check
  works on Prism 0.19 (Ruby 3.3) and Prism 2.

## [3.1.0] — 2026-11-06

A Bootstrap 5 preset for the linter, Ruby code that continues after an open bracket, and a faster formatter.

**New**
- `preset: bootstrap5` on DeprecatedClasses and DeprecatedAttributes: the Bootstrap 4 classes and component data
  attributes Bootstrap 5.3 renamed, breakpoints included (`text-md-right`). The rule's own entries go over it, and
  `~` drops one of the preset.
- A `(`, `[` or `{` that ends a line of code (`-`, `=`, `tag =`) continues it until the bracket closes, one argument
  per line; Slim refused these lines.

**Faster**
- `super-slim format` takes 3.5 s instead of 4.6 s on 7,500 templates at 120 columns.

**Fixed**
- `super-slim format` no longer refuses a trailing comma or call parentheses, and no longer takes `link_to(a) + b`
  for `link_to (a) + b`.
- In DeprecatedClasses, the longest prefix wins: `badge-promo-*` over `badge-*`.
- An empty `classes:` or `attributes:` no longer crashes the linter, and an unknown preset exits 64 with its name.

## [3.0.0] — 2026-11-05

SuperSlim is published as super-slim, the name of its command.

**Breaking**
- The gem is renamed `super-slim`: write `gem "super-slim"` in the Gemfile and `plugins: [super-slim]` in RuboCop's
  configuration. The `SuperSlim` module, `require "super_slim"`, the `super-slim` command and `.super-slim.yml` are
  unchanged.

## [2.2.0] — 2026-11-05

Six linter rules and options, `super-slim format`, and a formatter that no longer wraps a line RuboCop then refuses.

**New**
- `super-slim format` and the `format:` key of `.super-slim.yml`; `fmt` remains an alias for both.
- Every linter rule takes `include:` and `exclude:` globs.
- DeprecatedAttributes (`attributes: {old: new}`), and prefixes in DeprecatedClasses (`ml-*: ms-*`).
- UnescapedOutput (`==`, `html_safe`, `raw`, `#{{}}`), EmbeddedEngines (`forbidden_engines:`) and HardcodedText, off
  by default.

**Fixed**
- `super-slim format` keeps a line ending with an `if`, `unless`, `while`, `until` or `rescue` modifier on one line:
  wrapped, RuboCop refused it (Style/MultilineIfModifier).

## [2.1.0] — 2026-11-05

Slim's doctypes are back, for email layouts.

**New**
- `doctype transitional`, `strict` and `frameset` render the HTML 4.01 doctypes again, and XML templates take `1.1`,
  `basic`, `mobile`, `svg` and the XHTML 1.0 ones, as in Slim 5. Email layouts need `doctype transitional`:
  `<!DOCTYPE html>` switches Apple Mail and iOS Mail to standards mode, which opens a gap under the images of table
  cells.

## [2.0.1] — 2026-11-05

Two fixes to `super-slim`: braces around wrapped attributes, and `--help`.

**Fixed**
- `super-slim fmt` writes a space before `{` when it wraps attributes inside `{}` (`a.btn {`), as templates
  usually do; `(` and `[` stay attached to the tag.
- `super-slim --help`, `-h` and `help` print the usage on stdout and exit 0, after a command too
  (`super-slim fmt --help`). An unknown option, such as `fmt --chek`, fails with the usage and status 64
  instead of crashing.

## [2.0.0] — 2026-11-05

The gem takes the name SuperSlim, sheds what a Rails app doesn't need, and `super-slim fmt` wraps long lines.

**Breaking**
- The gem is renamed: `super_slim` in the Gemfile, the `SuperSlim` module, the `super-slim lint|fmt` command,
  `.super-slim.yml` and `plugins: [super_slim]` for RuboCop. Compiled templates name their variables
  `_super_slim1`, after the new name.
- No more Tilt adapter: its `require` has no replacement. Rails and `SuperSlim.compile` are unchanged.
- No more strict mode (`strict: true`): run `super-slim fmt --check` in CI instead.
- No more custom shortcuts: only `#id` and `.class`.
- Only `doctype 5`, `doctype html` and `doctype xml` remain; HTML 4 and XHTML doctypes, such as
  `doctype transitional`, raise `Invalid doctype`.

**New**
- `super-slim fmt` wraps lines longer than `fmt: max_line_length` in `.super-slim.yml`, off by default: a tag's
  attributes one per line inside `fmt: attribute_delimiters` (`"()"`, `"[]"` or `"{}"`), then the arguments of
  its Ruby code after each comma, four spaces deep when the line opens a block. A wrap is kept only when the
  compiled Ruby differs by whitespace alone.

## [1.1.0] — 2026-11-04

A RuboCop plugin that lints the Ruby inside templates with SuperSlim's own parser, and templates compiled up to 10% faster.

**New**
- A RuboCop plugin (`plugins: [super-slim]`) lints the Ruby of templates: `-` and `=` lines, code attributes, splats,
  `#{}` interpolations and `ruby:` blocks. Offenses point at their line and column in the `.slim` file, and
  autocorrection writes back into it. It replaces rubocop-slim, and with it slimi and Temple; unlike slimi, it
  also reads the output of a tag with whitespace markers and attributes (`span> title="x" = name`).

**Faster**
- Templates compile 7% faster without JIT and 10% faster with YJIT, with 11% to 16% fewer allocations (6,097
  public templates, Ruby 3.3 and 4.0). Rendering is unchanged.

**Fixed**
- `super-slim lint` reports the offenses of one line in the same order on every Ruby version.

## [1.0.0] — 2026-11-04

First stable release: a Slim 5 engine written from scratch, without Temple. 0.1.0 and 0.1.1 were previews. It
renders what Slim 5 renders with `format: :html, sort_attrs: false`, byte for byte; XML formats (`.xml`, `.rss`,
`.atom`) render as XML.

**New**
- Rails through a railtie, Tilt through a `require`, and `SuperSlim.compile` for plain Ruby.
- Every `-` and `=` stays on its template line, so backtraces point at the right one.
- `super-slim fmt`, which refuses any change to the compiled Ruby, and strict mode, which
  refuses unformatted templates at compile time.
- `super-slim lint` with 29 rules from slim-lint, haml-lint, erb_lint, Herb and eslint-plugin-jsx-a11y,
  configured in `.super-slim.yml`.
- `tailwind_classes`, off by default: class shortcuts read Tailwind class names.

**Left out**
- XHTML, `sort_attrs` and the other Temple options, the `coffee:`, `sass:`, `scss:`, `less:`, `erb:`,
  `builder:` and wiki engines, conditional comments, the `logic_less`, `translator`, `include` and `smart`
  plugins, and lambda shortcuts: each raises at compile time.

**Requires**
- Ruby 3.3 or later, every Ruby still maintained, Rails 8.0 or 8.1 for the railtie, and strscan 3.1.1 or later,
  newer than the one Ruby 3.3 ships.

[Unreleased]: https://github.com/levups/super-slim/compare/v3.4.1...HEAD
[3.4.1]: https://github.com/levups/super-slim/compare/v3.4.0...v3.4.1
[3.4.0]: https://github.com/levups/super-slim/compare/v3.3.0...v3.4.0
[3.3.0]: https://github.com/levups/super-slim/compare/v3.2.2...v3.3.0
[3.2.2]: https://github.com/levups/super-slim/compare/v3.2.1...v3.2.2
[3.2.1]: https://github.com/levups/super-slim/compare/v3.2.0...v3.2.1
[3.2.0]: https://github.com/levups/super-slim/compare/v3.1.1...v3.2.0
[3.1.1]: https://github.com/levups/super-slim/compare/v3.1.0...v3.1.1
[3.1.0]: https://github.com/levups/super-slim/compare/v3.0.0...v3.1.0
[3.0.0]: https://github.com/levups/super-slim/compare/v2.2.0...v3.0.0
[2.2.0]: https://github.com/levups/super-slim/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/levups/super-slim/compare/v2.0.1...v2.1.0
[2.0.1]: https://github.com/levups/super-slim/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/levups/super-slim/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/levups/super-slim/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/levups/super-slim/releases/tag/v1.0.0
