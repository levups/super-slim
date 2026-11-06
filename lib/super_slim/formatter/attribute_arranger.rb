# frozen_string_literal: true

module SuperSlim
  class Formatter
    # Rewrites the attributes of a tag written on one line: a literal id or class becomes a shortcut, a class named
    # twice goes, and the others follow one order: what the element is, then what it does, then how it reads aloud.
    class AttributeArranger
      # Only plain names: a dot between digits (`py-1.5`), `:` or `/` would read as another class under Tailwind.
      SHORTCUT = /[.#][A-Za-z_-][\w-]*/
      WHOLE_SHORTCUT = /\A#{SHORTCUT}\z/
      LITERAL_ID = /\Aid=(["'])([A-Za-z_][\w-]*)\1\z/
      LITERAL_CLASS = /\Aclass=(["']) *([\w-][\w\- ]*)\1\z/
      TAG_HEAD = /\A([\w:-]*)((?:#{SHORTCUT})*)([<>']*)\z/
      LEADING_SHORTCUTS = /\A( *[\w:-]*)((?:#{SHORTCUT})+)(?=[ =<>'\/]|: |\z)/
      ATTRIBUTE_AT_START = /\A#{Parser::CODE_ATTRIBUTE}/
      RANK_BY_NAME = {
        "id" => 0, "class" => 1, **%w[type name href src value for action method].to_h { [_1, 2] },
        "data-controller" => 4, "data-action" => 5, "role" => 7
      }.freeze

      def initialize(tailwind_classes:)
        @tailwind_classes = tailwind_classes
      end

      # Returns the line rearranged and its outline, or the line and its outline as they were when its tag has
      # nothing to rearrange. Without an outline, the line is read alone.
      def call(line, info = nil)
        info ||= line_info(line)
        return [line, info] unless info

        lists = info.attribute_lists
        return without_duplicate_shortcuts(line, info) if lists.nil?
        return [line, info] unless lists.size == 1

        indent = line[/\A */]
        first, last, spans = lists.first
        head = line[indent.size...first].rstrip
        # A dynamic tag, `*{tag: name}`, has no head to put shortcuts on.
        return [line, info] if head.empty? || !(head_parts = TAG_HEAD.match(head)) || head_parts[1].end_with?(":")

        attributes = spans.map { |span_first, span_last| line[span_first...span_last] }
        rest = line[last..]
        # Without delimiters, text that reads as an attribute would become one.
        if Parser::DELIMITERS.key?(line[first])
          return [line, info] if attributes.any? { !_1.include?("=") } || rest.match?(ATTRIBUTE_AT_START)
        end

        name, shortcuts, markers = head_parts.captures
        shortcuts = shortcuts.scan(SHORTCUT)
        # A splat merges attributes in the order they come.
        unless attributes.any? { _1.start_with?("*") }
          attributes = moved_to_shortcuts(attributes, shortcuts)
          attributes = attributes.sort_by.with_index { |attribute, index| [rank(attribute[/\A"?[^=\s"]+/].delete('"')), index] }
        end
        shortcuts.uniq!

        name = "" if name == "div" && !shortcuts.empty?
        rest = " #{rest.lstrip}" unless rest.empty? || rest.start_with?(" ")
        arranged = "#{indent}#{name}#{shortcuts.join}#{markers}#{" " unless attributes.empty?}#{attributes.join(" ")}#{rest}"
        outlined(arranged, line, info)
      end

      private

      # Appends a literal id or class to the shortcuts and returns the attributes left.
      def moved_to_shortcuts(attributes, shortcuts)
        class_kept = false
        attributes.reject do |attribute|
          if (id = LITERAL_ID.match(attribute)) && shortcuts.none? { _1.start_with?("#") }
            shortcuts << "##{id[2]}"
          elsif !class_kept && (class_shortcuts = literal_class_shortcuts(attribute, shortcuts))
            shortcuts.concat(class_shortcuts)
          else
            # Shortcuts come first among class values: a literal class after this one would move ahead of it.
            class_kept ||= attribute.start_with?("class=")
            false
          end
        end
      end

      # Nil when a class would be named twice: the check reads a shortcut and a class attribute as two values.
      def literal_class_shortcuts(attribute, shortcuts)
        return unless (classes = LITERAL_CLASS.match(attribute))

        class_shortcuts = classes[2].split.map { ".#{_1}" }
        class_shortcuts if class_shortcuts.all?(WHOLE_SHORTCUT) && class_shortcuts.uniq == class_shortcuts && !shortcuts.intersect?(class_shortcuts)
      end

      def without_duplicate_shortcuts(line, info)
        shortcuts = line[LEADING_SHORTCUTS, 2]&.scan(SHORTCUT)
        return [line, info] unless shortcuts && shortcuts.uniq.size < shortcuts.size

        outlined(line.sub(LEADING_SHORTCUTS) { "#{$1}#{shortcuts.uniq.join}" }, line, info)
      end

      # The outline of a line read alone, in columns of the indented line; nil when it doesn't parse alone.
      def line_info(line)
        indent = line[/\A */].size
        parser = Parser.new(outline: true, tailwind_classes: @tailwind_classes)
        parser.call(line.lstrip)
        info = parser.outline[1].dup
        info.output_column += indent if info.output_column
        info.attribute_lists = info.attribute_lists&.map do |first, last, spans|
          [first + indent, last + indent, spans.map { |span_first, span_last| [span_first + indent, span_last + indent] }]
        end
        info
      rescue Error
        nil
      end

      def outlined(arranged, line, info)
        return [line, info] if arranged == line

        arranged_info = line_info(arranged)
        arranged_info ? [arranged, arranged_info] : [line, info]
      end

      def rank(name)
        RANK_BY_NAME.fetch(name) do
          case name
          when /\Adata-.+-target\z/ then 5
          when /\Adata-/ then 6
          when /\Aaria-/ then 7
          else 3
          end
        end
      end
    end
  end
end
