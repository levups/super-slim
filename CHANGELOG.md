# Changelog

## Unreleased

- Runs on Ruby 3.3: the floor follows the oldest Ruby still maintained. SlimX now depends on strscan 3.1.1 or later,
  newer than the one Ruby 3.3 ships.

## 1.0.0 — 2026-11-03

First release: a Slim 5 engine written from scratch, without Temple.

- Renders what Slim 5 renders with `format: :html, sort_attrs: false`, byte for byte; XML formats (`.xml`,
  `.rss`, `.atom`) render as XML.
- Rails through a railtie, Tilt through `require "slimx/tilt"`, and `SlimX.compile` for plain Ruby.
- Every `-` and `=` stays on its template line, so backtraces point at the right one.
- `slimx fmt`, which refuses any change to the compiled Ruby, and strict mode (`SlimX.strict`), which
  refuses unformatted templates at compile time.
- `slimx lint` with 29 rules from slim-lint, haml-lint, erb_lint, Herb and eslint-plugin-jsx-a11y,
  configured in `.slimx.yml`.
- `tailwind_classes`, off by default: class shortcuts read Tailwind class names.
- Left out, with a compile-time error: XHTML, `sort_attrs` and the other Temple options, the `coffee:`,
  `sass:`, `scss:`, `less:`, `erb:`, `builder:` and wiki engines, conditional comments, the `logic_less`,
  `translator`, `include` and `smart` plugins, and lambda shortcuts.
