# frozen_string_literal: true

module SuperSlim
  class Formatter
    # Spreads a line of Ruby code over several: the arguments of its call, or the elements of its array or hash,
    # one per line, each line but the last ending with a comma. Slim, and Brakeman with it, reads a line ending with
    # a comma or a backslash as going on, but not one ending with an opening bracket. A call whose only argument is
    # itself a call, an array or a hash spreads that argument instead: `render Card.new(…)`.
    class CodeWrapper
      METHOD_NAME = /\A[a-z_][a-zA-Z0-9_]*[?!]?\z/
      # Rails runs a template inside a method, where `yield` is valid.
      TEMPLATE_METHOD = "def template\n"
      CODE_OFFSET = TEMPLATE_METHOD.bytesize

      # Returns the lines, the first one starting with head, or nil when the code has nothing to spread. An item
      # still longer than max_line_length spreads its own arguments or elements.
      def self.call(code, indent, head:, opens_block:, max_line_length:)
        new(code, indent, head:, opens_block:, max_line_length:).call
      end

      # `render Card.new title:` reads as if title went to render: arguments to `new` go in parentheses.
      def self.parenthesize_new(code)
        loop do
          statements, _opens_block = parse(code)
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

      # Returns the statements of the line and whether it opens a block: it then holds its `do` but not its `end`.
      # Their offsets count from CODE_OFFSET.
      def self.parse(code)
        parsed = Prism.parse("#{TEMPLATE_METHOD}#{code}\nend")
        opens_block = !parsed.success?
        parsed = Prism.parse("#{TEMPLATE_METHOD}#{code}\nend\nend") if opens_block
        [parsed.value.statements.body.first.body&.body || [], opens_block] if parsed.success? && parsed.comments.empty?
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

      # opens_block: whether the line has children, which Slim passes to its call as a block even without `do`.
      def initialize(code, indent, head:, opens_block:, max_line_length:)
        @code = code
        @indent = indent
        @head = head
        @opens_block = opens_block
        @max_line_length = max_line_length
      end

      def call
        statements, opens_block = self.class.parse(@code)
        return unless statements&.size == 1 && (node = spreadable(statements.first))

        # Set apart from the children of a line that opens a block.
        indent = @indent + (" " * ((@opens_block || opens_block) ? INDENT_WIDTH : 0))
        spread(node, CODE_OFFSET, CODE_OFFSET + @code.bytesize, @head, indent)
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
          (spreadable(items.first) if items) || (spreadable(node.receiver) if node.receiver.is_a?(Prism::ArrayNode) || node.receiver.is_a?(Prism::HashNode))
        when Prism::ArrayNode, Prism::HashNode
          # `%w[a b]` takes no commas.
          node if ["[", "{"].include?(node.opening) && node.elements.size > 1
        end
      end

      # The lines of the code from first to last after prefix, node's first item on the first line, and each other
      # one on a line of its own, indented one level deeper than indent.
      def spread(node, first, last, prefix, indent)
        items = node.is_a?(Prism::CallNode) ? self.class.arguments_of(node) : node.elements
        # `hint: -> do` ends past the line, with the children of the line.
        return if self.class.end_offset(items.last) > CODE_OFFSET + @code.bytesize

        item_indent = indent + (" " * INDENT_WIDTH)
        head = prefix + slice(first, node.opening_loc&.end_offset || items.first.location.start_offset)
        tail = slice(node.closing_loc&.start_offset || self.class.end_offset(items.last), last)
        # The last item carries what closes the node: brackets, a block, a method called on the spread array.
        suffixes = items.map { _1.equal?(items.last) ? tail : "," }
        first_lines = item_lines(items.first, head, item_indent, suffixes.first)
        # A first item that passes the limit after the head goes to a line of its own, after a backslash.
        if first_lines.first.size > @max_line_length && !head.strip.empty?
          backslash = head.match?(Parser::OPENING_BRACKET_AT_LINE_END) ? "\\" : " \\"
          first_lines = ["#{head.rstrip}#{backslash}", *item_lines(items.first, item_indent, item_indent, suffixes.first)]
        end
        *lines, last_line = first_lines + items.zip(suffixes).drop(1).flat_map { |item, suffix| item_lines(item, item_indent, item_indent, suffix) }
        lines + closing_lines(last_line, tail, item_indent)
      end

      # What closes the last item goes to the next line after a backslash when the last line would pass the limit.
      def closing_lines(last_line, tail, indent)
        return [last_line] if tail.empty? || last_line.size <= @max_line_length

        after_backslash = ["#{last_line.delete_suffix(tail)} \\", indent + tail.lstrip]
        (after_backslash.map(&:size).max < last_line.size) ? after_backslash : [last_line]
      end

      # The lines of item after prefix, then suffix.
      def item_lines(item, prefix, indent, suffix)
        item_end = self.class.end_offset(item)
        line = "#{prefix}#{slice(item.location.start_offset, item_end)}#{suffix}"
        return [line] if line.size <= @max_line_length

        nested = spreadable(item.is_a?(Prism::AssocNode) ? item.value : item)
        lines = nested && spread(nested, item.location.start_offset, item_end, prefix, indent)
        return [line] unless lines

        lines[-1] += suffix
        lines
      end

      # From offsets in the parsed source, up to the end of the line by default.
      def slice(first, last = CODE_OFFSET + @code.bytesize)
        @code.byteslice((first - CODE_OFFSET)...(last - CODE_OFFSET))
      end
    end
  end
end
