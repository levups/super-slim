# frozen_string_literal: true

module SuperSlim
  class Formatter
    # Spreads a line of Ruby code over several: the arguments of its call, or the elements of its array or hash,
    # one per line, each followed by a comma, between brackets that close on a line of their own. A call whose only
    # argument is itself a call, an array or a hash spreads that argument instead: `render Card.new(…)`.
    class CodeWrapper
      METHOD_NAME = /\A[a-z_][a-zA-Z0-9_]*[?!]?\z/
      # Rails runs a template inside a method, where `yield` is valid.
      TEMPLATE_METHOD = "def template\n"
      CODE_OFFSET = TEMPLATE_METHOD.bytesize

      # Returns the lines after the first one's indentation, or nil when the code has nothing to spread.
      def self.call(code, indent, block:)
        new(code, indent, block:).call
      end

      # `render Card.new title:` reads as if title went to render: arguments to `new` go in parentheses.
      def self.parenthesize_new(code)
        loop do
          statements, _block = parse(code)
          call = statements && bare_new(statements)
          return code unless call

          name_end = call.message_loc.end_offset - CODE_OFFSET
          arguments_start = call.arguments.location.start_offset - CODE_OFFSET
          arguments_end = call.arguments.location.end_offset - CODE_OFFSET
          code = "#{code.byteslice(0, name_end)}(#{code.byteslice(arguments_start...arguments_end)})#{code.byteslice(arguments_end..)}"
        end
      end

      def self.bare_new(statements)
        nodes = statements.dup
        while (node = nodes.pop)
          return node if node.is_a?(Prism::CallNode) && node.name == :new && node.arguments && node.opening_loc.nil?

          nodes.concat(node.child_nodes.compact)
        end
      end

      # Returns the statements of the line and whether it opens a block: it then holds its `do` but not its `end`.
      # Their offsets count from CODE_OFFSET.
      def self.parse(code)
        parsed = Prism.parse("#{TEMPLATE_METHOD}#{code}\nend")
        block = !parsed.success?
        parsed = Prism.parse("#{TEMPLATE_METHOD}#{code}\nend\nend") if block
        [parsed.value.statements.body.first.body&.body || [], block] if parsed.success? && parsed.comments.empty?
      end

      # block: whether the line has children, which Slim passes to its call as a block even without `do`.
      def initialize(code, indent, block:)
        @code = code
        @indent = indent
        @block = block
      end

      def call
        statements, block = self.class.parse(@code)
        return unless statements&.size == 1 && (node = spreadable(statements.first))

        spread(node, @block || block)
      end

      private

      def spreadable(node)
        node = node.value if node.type.end_with?("_write_node") && node.respond_to?(:value)
        case node
        when Prism::CallNode
          items = call_items(node)
          # An operator such as `+` has no parentheses to add.
          return if items.nil? || (node.opening_loc.nil? && !METHOD_NAME.match?(node.name.to_s))
          return spreadable(items.first) if items.size == 1

          node if items.size > 1
        when Prism::ArrayNode, Prism::HashNode
          node if node.opening_loc && node.elements.size > 1
        end
      end

      def call_items(call)
        return if call.message_loc.nil? || (call.arguments.nil? && !call.block.is_a?(Prism::BlockArgumentNode))

        items = (call.arguments&.arguments || []).flat_map { |argument| argument.is_a?(Prism::KeywordHashNode) ? argument.elements : [argument] }
        call.block.is_a?(Prism::BlockArgumentNode) ? [*items, call.block] : items
      end

      def spread(node, block)
        items = node.is_a?(Prism::CallNode) ? call_items(node) : node.elements
        closing_indent = @indent + (" " * (block ? 2 * INDENT_WIDTH : INDENT_WIDTH))
        item_indent = closing_indent + (" " * INDENT_WIDTH)
        head, tail =
          if node.opening_loc
            [slice(CODE_OFFSET, node.opening_loc.end_offset), slice(node.closing_loc.start_offset)]
          else
            ["#{slice(CODE_OFFSET, node.message_loc.end_offset)}(", ")#{slice(end_offset(items.last))}"]
          end
        [head, *items.map { |item| "#{item_indent}#{slice(item.location.start_offset, end_offset(item))}," }, closing_indent + tail]
      end

      # Prism 0.19 (Ruby 3.3) ends a call that takes a block argument before its closing parenthesis: `f(&x`.
      def end_offset(node)
        closing = node.closing_loc if node.respond_to?(:closing_loc)
        closing ? [node.location.end_offset, closing.end_offset].max : node.location.end_offset
      end

      # From offsets in the parsed source, up to the end of the line by default.
      def slice(first, last = CODE_OFFSET + @code.bytesize)
        @code.byteslice((first - CODE_OFFSET)...(last - CODE_OFFSET))
      end
    end
  end
end
