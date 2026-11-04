# Changelog

## 1.0.0

First stable release: a Slim 5 engine written from scratch, without Temple. 0.1.0 and 0.1.1 were previews.

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
- Runs on Ruby 3.3 and later, every Ruby still maintained, and on Rails 8.0 and 8.1. Depends on strscan 3.1.1 or
  later, newer than the one Ruby 3.3 ships.
- Documentation at https://next-gen-gems.github.io/slimx/, linked from the gem's RubyGems page.
