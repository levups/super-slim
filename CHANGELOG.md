# Changelog

## 1.0.0 — 2026-11-03

- The gem now lives at https://github.com/next-gen-gems/slimx, linked from its RubyGems page as source code and
  changelog.
- `slimx lint`: UnnecessaryStringOutput no longer suggests moving text starting with `(`, `[`, `{`, `=`, `*`
  or `/` inline after its tag, where it would read as attributes or output: `span = "(estimate)"` is told to
  write `| (estimate)` on its own line, under the tag.

## 0.1.1 — 2026-11-01

- `slimx lint`: the Zwsp rule no longer flags the zero-width joiner between two emoji pictographs, as in 🐈‍⬛
  or 👩🏻‍💻. A zero-width character anywhere else is still reported, including a joiner or non-joiner glued to
  an emoji.

## 0.1.0 — 2026-11-01

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
