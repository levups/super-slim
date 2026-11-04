# Changelog

## [Unreleased]

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

[Unreleased]: https://github.com/next-gen-gems/slimx/compare/v1.1.0...HEAD
[1.1.0]: https://github.com/next-gen-gems/slimx/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/next-gen-gems/slimx/releases/tag/v1.0.0
