# frozen_string_literal: true

module SuperSlim
  class Formatter
    # Rewrites the attributes of a tag written on one line: a literal id or class becomes a shortcut, a class named
    # twice goes, and the others follow one order: what the element is, then what it does, then how it reads aloud.
    class AttributeArranger
      LITERAL_ID = /\Aid=(["'])([A-Za-z_][\w-]*)\1\z/
      LITERAL_CLASS = /\Aclass=(["'])([\w\- ]+)\1\z/
      SHORTCUT_NAME = /\A[A-Za-z_-][\w-]*\z/
      HEAD = /\A([\w:-]*)((?:[.#][\w-]+)*)([<>']*)\z/
      LEADING_SHORTCUTS = /\A( *[\w:-]*)((?:[.#][\w-]+)+)/
      # What the element is, then what it does, then how it reads aloud; any other attribute ranks 3.
      RANK_BY_NAME = {
        "id" => 0, "class" => 1, **%w[type name href src value for action method].to_h { [_1, 2] },
        "data-controller" => 4, "data-action" => 5, "role" => 7
      }.freeze

      def initialize(tailwind_classes:)
        @tailwind_classes = tailwind_classes
      end

      def self.duplicate_shortcut?(line)
        shortcuts = line[LEADING_SHORTCUTS, 2]&.scan(/[.#][\w-]+/)
        shortcuts && shortcuts.uniq.size < shortcuts.size
      end

      # Returns the line rearranged and its outline, or the line and its outline as they were when its tag has
      # nothing to rearrange. Without an outline, the line is read alone.
      def call(line, info = nil)
        info ||= line_info(line)
        return [line, info] unless info

        lists = info.attribute_lists
        if lists.nil? && self.class.duplicate_shortcut?(line)
          return outlined(line.sub(LEADING_SHORTCUTS) { "#{$1}#{$2.scan(/[.#][\w-]+/).uniq.join}" }, line, info)
        end
        return [line, info] unless lists&.size == 1

        indent = line[/\A */]

        first, last, spans = lists.first
        head = line[indent.size...first].rstrip
        # A dynamic tag, `*{tag: name}`, has no head to put shortcuts on.
        return [line, info] if head.empty? || !(head_parts = HEAD.match(head)) || head_parts[1].end_with?(":")

        attributes = spans.map { |span_first, span_last| line[span_first...span_last] }
        delimited = line[first].match?(/[(\[{]/)
        return [line, info] if delimited && attributes.any? { !_1.include?("=") }

        name, shortcuts, markers = head_parts.captures
        shortcuts = shortcuts.scan(/[.#][\w-]+/)
        attributes = attributes.reject do |attribute|
          if (id = LITERAL_ID.match(attribute)) && shortcuts.none? { _1.start_with?("#") }
            shortcuts << "##{id[2]}"
          elsif (classes = LITERAL_CLASS.match(attribute)) && classes[2].split.all?(SHORTCUT_NAME)
            shortcuts.concat(classes[2].split.map { ".#{_1}" })
          end
        end
        shortcuts.uniq!
        attributes = attributes.each_with_index.sort_by { |attribute, index| [rank(attribute[/\A"?[^=\s"]+/].delete('"')), index] }.map(&:first) unless attributes.any? { _1.start_with?("*") }

        name = "" if name == "div" && !shortcuts.empty?
        rest = line[last..]
        rest = " #{rest.lstrip}" unless rest.empty? || rest.start_with?(" ")
        arranged = "#{indent}#{name}#{shortcuts.join}#{markers}#{" " unless attributes.empty?}#{attributes.join(" ")}#{rest}"
        outlined(arranged, line, info)
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

      private

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
