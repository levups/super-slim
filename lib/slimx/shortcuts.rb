# frozen_string_literal: true

module SlimX
  class Shortcuts
    DEFAULT = {"#" => {attr: "id"}, "." => {attr: "class"}}.freeze
    DEFAULT_TAG = "div"

    attr_reader :tag_by_shortcut, :attributes_by_shortcut, :additional_attributes_by_shortcut, :attribute_pattern, :tag_pattern

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

    @shortcuts_by_definitions = {}

    def self.for(definitions, tailwind_classes: false)
      @shortcuts_by_definitions[[definitions, tailwind_classes]] ||= new(definitions, tailwind_classes:).freeze
    end

    def initialize(definitions, tailwind_classes: false)
      @tag_by_shortcut = {}
      @attributes_by_shortcut = {}
      @additional_attributes_by_shortcut = {}
      definitions.each { |shortcut, definition| register(shortcut, definition) }

      attribute_keys = Regexp.union(@attributes_by_shortcut.keys.sort_by { -it.size })
      name_part = tailwind_classes ? TAILWIND_NAME_PART : SLIM_NAME_PART
      @attribute_pattern = /\A(#{attribute_keys}+)((?:#{name_part})*)/
      tag_keys = Regexp.union(@tag_by_shortcut.keys.sort_by { -it.size })
      @tag_pattern = /\A(?:#{tag_keys}|\*(?=[^\s]+)|(\p{Word}(?:\p{Word}|:|-)*\p{Word}|\p{Word}+))/
    end

    private

    def register(shortcut, definition)
      valid = (definition[:attr] || definition[:tag]) && (definition.keys - %i[attr tag additional_attrs]).empty?
      raise ArgumentError, "Shortcut requires :tag and/or :attr" unless valid

      raise ArgumentError, "Lambda shortcuts are not supported" if definition[:attr].is_a?(Proc)

      @tag_by_shortcut[shortcut] = definition[:tag] || DEFAULT_TAG
      if (definition.key?(:attr) || definition.key?(:additional_attrs)) && shortcut.match?(/(\p{Word}|-)/)
        raise ArgumentError, "You can only use special characters for attribute shortcuts"
      end

      @attributes_by_shortcut[shortcut] = Array(definition[:attr]) if definition.key?(:attr)
      @additional_attributes_by_shortcut[shortcut] = definition[:additional_attrs] if definition.key?(:additional_attrs)
    end
  end
end
