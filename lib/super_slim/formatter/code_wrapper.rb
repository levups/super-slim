# frozen_string_literal: true

module SuperSlim
  class Formatter
    # Spreads a line of Ruby code over several: the arguments of its call, or the elements of its array or hash, one
    # per line, each but the last followed by a comma, the only line ending besides a backslash after which Slim
    # continues the code: `render "card",` then `post:`. A call whose only argument is itself a call, an array or a
    # hash spreads that argument instead: `render Card.new(title:,`.
    class CodeWrapper
      METHOD_NAME = /\A[a-z_][a-zA-Z0-9_]*[?!]?\z/
      # Rails runs a template inside a method, where `yield` is valid.
      TEMPLATE_METHOD = "def template\n"
      CODE_OFFSET = TEMPLATE_METHOD.bytesize

      # Returns the lines of lead, what precedes the code on its line, then the code; nil when the code has nothing
      # to spread. An item still longer than max_line_length spreads its own arguments or elements.
      def self.call(code, lead, max_line_length:)
        new(code, lead, max_line_length:).call
      end

      # `render Card.new title:` reads as if title went to render: arguments to `new` go in parentheses.
      def self.parenthesize_new(code)
        loop do
          statements = parse(code)
          call = statements && new_without_parentheses(statements)
          return code unless call

          arguments = arguments_of(call)
          name_end = call.message_loc.end_offset - CODE_OFFSET
          arguments_start = arguments.first.location.start_offset - CODE_OFFSET
          arguments_end = end_offset(arguments.last) - CODE_OFFSET
          return code if arguments_end > code.bytesize

          code = "#{code.byteslice(0, name_end)}(#{code.byteslice(arguments_start...arguments_end)})#{code.byteslice(arguments_end..)}"
        end
      end

      def self.new_without_parentheses(statements)
        nodes = statements.dup
        while (node = nodes.pop)
          return node if node.is_a?(Prism::CallNode) && node.name == :new && node.opening_loc.nil? && arguments_of(node)

          nodes.concat(node.child_nodes.compact)
        end
      end
      private_class_method :new_without_parentheses

      # Returns the statements of the line, whose offsets count from CODE_OFFSET. A line that opens a block holds its
      # `do` but not its `end`.
      def self.parse(code)
        parsed = Prism.parse("#{TEMPLATE_METHOD}#{code}\nend")
        parsed = Prism.parse("#{TEMPLATE_METHOD}#{code}\nend\nend") unless parsed.success?
        parsed.value.statements.body.first.body&.body || [] if parsed.success? && parsed.comments.empty?
      end

      # Positional and keyword arguments, then the block argument; nil when the call takes none.
      def self.arguments_of(call)
        arguments = (call.arguments&.arguments || []).flat_map { |argument| argument.is_a?(Prism::KeywordHashNode) ? argument.elements : [argument] }
        arguments += [call.block] if call.block.is_a?(Prism::BlockArgumentNode)
        arguments unless call.message_loc.nil? || arguments.empty?
      end

      # 2026-11: Prism 0.19 (Ruby 3.3) ends a call that takes a block argument, and any node around it, before the
      # call's closing parenthesis: `f(&x`.
      def self.end_offset(node)
        closing = node.closing_loc if node.respond_to?(:closing_loc)
        child_ends = node.child_nodes.filter_map { |child| end_offset(child) if child }
        [node.location.end_offset, closing&.end_offset || 0, *child_ends].max
      end

      def initialize(code, lead, max_line_length:)
        @code = code
        @lead = lead
        @max_line_length = max_line_length
      end

      def call
        statements = self.class.parse(@code)
        return unless statements&.size == 1 && (node = spreadable(statements.first))

        argument_indent = @lead[/\A */] + (" " * 2 * INDENT_WIDTH)
        lines = spread(node, @lead, CODE_OFFSET, CODE_OFFSET + @code.bytesize, argument_indent)
        lines if lines && longest(lines) < (@lead + @code).size
      end

      private

      def spreadable(node)
        node = node.value if node.type.end_with?("_write_node") && node.respond_to?(:value)
        case node
        when Prism::CallNode
          items = self.class.arguments_of(node)
          # An operator such as `+` has no parentheses to add, and `list[index] = value` holds value in its arguments.
          return if node.name.end_with?("=") || (node.opening_loc.nil? && !METHOD_NAME.match?(node.name.to_s))
          return node if items && items.size > 1

          # `[a, b].join(" ")` spreads its array.
          (items && spreadable(items.first)) || (spreadable(node.receiver) if node.receiver in Prism::ArrayNode | Prism::HashNode)
        when Prism::ArrayNode, Prism::HashNode
          # `%w[a b]` takes no commas.
          node if ["[", "{"].include?(node.opening) && node.elements.size > 1
        end
      end

      # The lines of lead then the code from first to last, with node's items at indent after the first.
      def spread(node, lead, first, last, indent)
        items = node.is_a?(Prism::CallNode) ? self.class.arguments_of(node) : node.elements
        items_end = self.class.end_offset(items.last)
        # `hint: -> do` ends past the line, with the children of the line.
        return if items_end > CODE_OFFSET + @code.bytesize

        lines = first_item_lines(items.first, lead + slice(first, items.first.location.start_offset), indent)
        items.drop(1).each { |item| lines.concat(item_lines(item, indent)) }
        lines + closing_lines(lines.pop.delete_suffix(","), slice(items_end, last), indent)
      end

      # A first item that doesn't fit after its call starts the next line, after a backslash, when that line starts
      # further left.
      def first_item_lines(item, lead, indent)
        if "#{lead}#{code_of(item)},".size > @max_line_length && lead.size > indent.size
          ["#{lead.rstrip} \\", *item_lines(item, indent)]
        else
          item_lines(item, indent, lead)
        end
      end

      # The lines of lead then item and a comma; the items it spreads go deeper than indent.
      def item_lines(item, indent, lead = indent)
        line = "#{lead}#{code_of(item)},"
        return [line] if line.size <= @max_line_length

        nested = spreadable(item.is_a?(Prism::AssocNode) ? item.value : item)
        lines = nested && spread(nested, lead, item.location.start_offset, self.class.end_offset(item), indent + (" " * INDENT_WIDTH))
        lines ? [*lines[0...-1], "#{lines.last},"] : [line]
      end

      # The last item's line then what closes it: brackets, a block, a method called on the spread array. When that
      # would pass the limit, they go to the next line after a backslash.
      def closing_lines(last_line, closing, indent)
        on_one_line = [last_line + closing]
        return on_one_line if closing.empty? || on_one_line.first.size <= @max_line_length

        after_backslash = ["#{last_line} \\", indent + closing.lstrip]
        (longest(after_backslash) < on_one_line.first.size) ? after_backslash : on_one_line
      end

      def code_of(item)
        slice(item.location.start_offset, self.class.end_offset(item))
      end

      def longest(lines)
        lines.map(&:size).max
      end

      def slice(first, last)
        @code.byteslice((first - CODE_OFFSET)...(last - CODE_OFFSET))
      end
    end
  end
end
