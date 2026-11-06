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
      def self.call(code, indent, opens_block:)
        new(code, indent, opens_block:).call
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
      def initialize(code, indent, opens_block:)
        @code = code
        @indent = indent
        @opens_block = opens_block
      end

      def call
        statements, opens_block = self.class.parse(@code)
        return unless statements&.size == 1 && (node = spreadable(statements.first))

        spread(node, @opens_block || opens_block)
      end

      private

      def spreadable(node)
        node = node.value if node.type.end_with?("_write_node") && node.respond_to?(:value)
        case node
        when Prism::CallNode
          items = self.class.arguments_of(node)
          # An operator such as `+` has no parentheses to add, and `list[index] = value` holds value in its arguments.
          return if items.nil? || node.name.end_with?("=") || (node.opening_loc.nil? && !METHOD_NAME.match?(node.name.to_s))
          return spreadable(items.first) if items.size == 1

          node
        when Prism::ArrayNode, Prism::HashNode
          # `%w[a b]` takes no commas.
          node if ["[", "{"].include?(node.opening) && node.elements.size > 1
        end
      end

      def spread(node, opens_block)
        items = node.is_a?(Prism::CallNode) ? self.class.arguments_of(node) : node.elements
        # `hint: -> do` ends past the line, with the children of the line.
        return if self.class.end_offset(items.last) > CODE_OFFSET + @code.bytesize

        closing_indent = @indent + (" " * (opens_block ? 2 * INDENT_WIDTH : INDENT_WIDTH))
        item_indent = closing_indent + (" " * INDENT_WIDTH)
        head, tail =
          if node.opening_loc
            [slice(CODE_OFFSET, node.opening_loc.end_offset), slice(node.closing_loc.start_offset)]
          else
            ["#{slice(CODE_OFFSET, node.message_loc.end_offset)}(", ")#{slice(self.class.end_offset(items.last))}"]
          end
        item_lines = items.map do |item|
          # A comma after `&block` is a syntax error.
          comma = "," unless item.is_a?(Prism::BlockArgumentNode)
          "#{item_indent}#{slice(item.location.start_offset, self.class.end_offset(item))}#{comma}"
        end
        [head, *item_lines, closing_indent + tail]
      end

      # From offsets in the parsed source, up to the end of the line by default.
      def slice(first, last = CODE_OFFSET + @code.bytesize)
        @code.byteslice((first - CODE_OFFSET)...(last - CODE_OFFSET))
      end
    end
  end
end
