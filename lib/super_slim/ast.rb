# frozen_string_literal: true

module SuperSlim
  module AST
    NEWLINE = :newline

    # Structs, not Data: Data.new allocates two more objects per node and is 2.8x slower, on every template line.
    Static = Struct.new(:text)
    Text = Struct.new(:text)
    TextBlock = Struct.new(:children)
    InlineHtml = Struct.new(:text, :children)
    Tag = Struct.new(:name, :attributes, :content)
    Control = Struct.new(:code, :children)
    Output = Struct.new(:code, :escape, :children)
    Comment = Struct.new(:children)
    Doctype = Struct.new(:type)
    Embedded = Struct.new(:engine, :children, :attributes)

    StaticAttribute = Struct.new(:name, :value)
    QuotedAttribute = Struct.new(:name, :escape, :text)
    CodeAttribute = Struct.new(:name, :escape, :code)
    BooleanAttribute = Struct.new(:name)
    Splat = Struct.new(:code)

    def self.empty?(nodes)
      nodes.all?(NEWLINE)
    end

    # Once compiled, a text block with no text leaves nothing behind: Slim then closes a void tag holding one.
    def self.renders_nothing?(nodes)
      nodes.all? { |node| node == NEWLINE || (node.is_a?(TextBlock) && renders_nothing?(node.children)) }
    end
  end
end
