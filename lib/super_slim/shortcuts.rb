# frozen_string_literal: true

module SuperSlim
  # `#name` sets the id and `.name` a class, on a div unless a tag name comes first.
  module Shortcuts
    ATTRIBUTE_BY_SHORTCUT = {"#" => "id", "." => "class"}.freeze
    DEFAULT_TAG = "div"

    SLIM_NAME_PART = /\p{Word}|-|\/\d+|:(?:\w|-)+/
    # Tailwind class names: arbitrary values in brackets (one level of nesting, no whitespace), CSS variables in
    # parentheses after a dash, variants joined by `:` (`: ` with a space still nests a tag), `!` and `@`,
    # `*:` child variants, fractions and opacities after `/` (a final `/` still closes the tag), and decimals
    # such as `py-1.5`, where a dot between two digits does not start a new class.
    # Tailwind never puts a bracket right after a letter or a digit: `.btn[href="/"]` stays an attribute list.
    TAILWIND_NAME_PART = %r{
      \p{Word} | - | ! | @ | \*(?=:)
      | :(?=[\p{Word}\[(!@*-])
      | /(?=[\p{Word}\[(])
      | (?<=\d)\.(?=\d)
      | (?<![\p{Word}\])]) \[ (?:[^\[\]\s] | \[[^\[\]\s]*\])+ \]
      | (?<=-)\( (?:[^()\s] | \([^()\s]*\))+ \)
    }x

    ATTRIBUTE_PATTERN = /\A([#.]+)((?:#{SLIM_NAME_PART})*)/
    TAILWIND_ATTRIBUTE_PATTERN = /\A([#.]+)((?:#{TAILWIND_NAME_PART})*)/
    TAG_PATTERN = /\A(?:[#.]|\*(?=[^\s]+)|(\p{Word}(?:\p{Word}|:|-)*\p{Word}|\p{Word}+))/
  end
end
