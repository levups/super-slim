# Changelog

## [Unreleased]

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

SlimX becomes SuperSlim, sheds what a Rails app doesn't need, and `super-slim fmt` wraps long lines.

**Breaking**
- The gem is renamed: `super_slim` in the Gemfile, the `SuperSlim` module, the `super-slim lint|fmt` command,
  `.super-slim.yml` and `plugins: [super_slim]` for RuboCop. Compiled templates name their variables
  `_super_slim1` instead of `_slimx1`.
- No more Tilt adapter: `require "slimx/tilt"` has no replacement. Rails and `SuperSlim.compile` are unchanged.
- No more strict mode (`SlimX.strict`, `strict: true`): run `super-slim fmt --check` in CI instead.
- No more custom shortcuts: only `#id` and `.class`.
- Only `doctype 5`, `doctype html` and `doctype xml` remain; HTML 4 and XHTML doctypes, such as
  `doctype transitional`, raise `Invalid doctype`.

**New**
- `super-slim fmt` wraps lines longer than `fmt: max_line_length` in `.super-slim.yml`, off by default: a tag's
  attributes one per line inside `fmt: attribute_delimiters` (`"()"`, `"[]"` or `"{}"`), then the arguments of
  its Ruby code after each comma, four spaces deep when the line opens a block. A wrap is kept only when the
  compiled Ruby differs by whitespace alone.

## [1.1.0] — 2026-11-04

A RuboCop plugin that lints the Ruby inside templates with SlimX's own parser, and templates compiled up to 10% faster.

**New**
- A RuboCop plugin (`plugins: [slimx]`) lints the Ruby of templates: `-` and `=` lines, code attributes, splats,
  `#{}` interpolations and `ruby:` blocks. Offenses point at their line and column in the `.slim` file, and
  autocorrection writes back into it. It replaces rubocop-slim, and with it slimi and Temple; unlike slimi, it
  also reads the output of a tag with whitespace markers and attributes (`span> title="x" = name`).

**Faster**
- Templates compile 7% faster without JIT and 10% faster with YJIT, with 11% to 16% fewer allocations (6,097
  public templates, Ruby 3.3 and 4.0). Rendering is unchanged.

**Fixed**
- `slimx lint` reports the offenses of one line in the same order on every Ruby version.

## [1.0.0] — 2026-11-04

First stable release: a Slim 5 engine written from scratch, without Temple. 0.1.0 and 0.1.1 were previews. It
renders what Slim 5 renders with `format: :html, sort_attrs: false`, byte for byte; XML formats (`.xml`, `.rss`,
`.atom`) render as XML.

**New**
- Rails through a railtie, Tilt through `require "slimx/tilt"`, and `SlimX.compile` for plain Ruby.
- Every `-` and `=` stays on its template line, so backtraces point at the right one.
- `slimx fmt`, which refuses any change to the compiled Ruby, and strict mode (`SlimX.strict`), which
  refuses unformatted templates at compile time.
- `slimx lint` with 29 rules from slim-lint, haml-lint, erb_lint, Herb and eslint-plugin-jsx-a11y,
  configured in `.slimx.yml`.
- `tailwind_classes`, off by default: class shortcuts read Tailwind class names.

**Left out**
- XHTML, `sort_attrs` and the other Temple options, the `coffee:`, `sass:`, `scss:`, `less:`, `erb:`,
  `builder:` and wiki engines, conditional comments, the `logic_less`, `translator`, `include` and `smart`
  plugins, and lambda shortcuts: each raises at compile time.

**Requires**
- Ruby 3.3 or later, every Ruby still maintained, Rails 8.0 or 8.1 for the railtie, and strscan 3.1.1 or later,
  newer than the one Ruby 3.3 ships.

[Unreleased]: https://github.com/levups/super-slim/compare/v2.2.0...HEAD
[2.2.0]: https://github.com/levups/super-slim/compare/v2.1.0...v2.2.0
[2.1.0]: https://github.com/levups/super-slim/compare/v2.0.1...v2.1.0
[2.0.1]: https://github.com/levups/super-slim/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/levups/super-slim/compare/v1.1.0...v2.0.0
[1.1.0]: https://github.com/next-gen-gems/slimx/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/next-gen-gems/slimx/releases/tag/v1.0.0
