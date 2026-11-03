# frozen_string_literal: true

module SlimX
  class Compiler
    include AST

    VOID_ELEMENTS = %w[area base br col embed hr img input keygen link menuitem meta param source track wbr].to_h { [_1, true] }.freeze
    HYPHENATED_ATTRIBUTES = %w[data aria].freeze
    DOCTYPES = {
      html: {
        "5" => "<!DOCTYPE html>",
        "html" => "<!DOCTYPE html>",
        "strict" => '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01//EN" "http://www.w3.org/TR/html4/strict.dtd">',
        "frameset" => '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Frameset//EN" "http://www.w3.org/TR/html4/frameset.dtd">',
        "transitional" => '<!DOCTYPE html PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">'
      },
      xml: {
        "1.1" => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.1//EN" "http://www.w3.org/TR/xhtml11/DTD/xhtml11.dtd">',
        "5" => "<!DOCTYPE html>",
        "html" => "<!DOCTYPE html>",
        "strict" => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Strict//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-strict.dtd">',
        "frameset" => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Frameset//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-frameset.dtd">',
        "mobile" => '<!DOCTYPE html PUBLIC "-//WAPFORUM//DTD XHTML Mobile 1.2//EN" "http://www.openmobilealliance.org/tech/DTD/xhtml-mobile12.dtd">',
        "basic" => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML Basic 1.1//EN" "http://www.w3.org/TR/xhtml-basic/xhtml-basic11.dtd">',
        "transitional" => '<!DOCTYPE html PUBLIC "-//W3C//DTD XHTML 1.0 Transitional//EN" "http://www.w3.org/TR/xhtml1/DTD/xhtml1-transitional.dtd">',
        "svg" => '<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.1//EN" "http://www.w3.org/Graphics/SVG/1.1/DTD/svg11.dtd">'
      }
    }.freeze

    BLOCK_SELF_OPENING = /(\A(if|unless|else|elsif|when|in|begin|rescue|ensure|case)\b)|\bdo\s*(\|[^|]*\|\s*)?\z/
    BLOCK_OPENING = /\A(if|begin|unless|else|elsif|when|in|rescue|ensure)\b|\bdo\s*(\|[^|]*\|)?\s*$/
    BLOCK_CONTINUATION = /\A(else|elsif|when|in|rescue|ensure)\b/
    EXPLICIT_END = /\Aend\b/
    CAPTURED_OUTPUT = /\A(if|unless)\b|\bdo\s*(\|[^|]*\|)?\s*$/

    ESCAPED_INTERPOLATION = /\A\\#\{/
    INTERPOLATION = /\A#\{((?>[^{}]|(\{(?>[^{}]|\g<1>)*\}))*)\}/
    UNESCAPED_INTERPOLATION_CODE = /\A\{.*\}\Z/
    INTERPOLATION_FREE_TEXT = /\A([#\\]?[^#\\]*([#\\][^\\#\{][^#\\]*)*)/ # rubocop:disable Style/RedundantRegexpEscape -- `#{` would open an interpolation

    def initialize(format: :html, rails: false, html_safe: String.method_defined?(:html_safe?), preamble: nil, postamble: nil)
      raise ArgumentError, "Invalid format #{format.inspect}" unless DOCTYPES.key?(format)

      @xml = format == :xml
      @format = format
      @rails = rails
      @html_safe = html_safe
      @escape_function = html_safe ? "::SlimX::Runtime.escape_html_safe" : "::ERB::Escape.html_escape"
      @preamble = preamble
      @postamble = postamble
    end

    def call(nodes)
      @code = +""
      @static = +""
      @variable_count = 0
      @buffer = @rails ? OutputBuffer.new : StringBuffer.new("_buf", @escape_function)

      emit_code(@buffer.open)
      emit_static(@preamble) if @preamble
      compile_children(nodes)
      emit_static(@postamble) if @postamble
      emit_code(@buffer.close)
      @code
    end

    private

    def compile_children(nodes)
      block_open = false
      nodes.each do |node|
        if node.is_a?(Control)
          raise Error, "Explicit end statements are forbidden" if node.code.match?(EXPLICIT_END)

          emit_code("end") if block_open && !node.code.match?(BLOCK_CONTINUATION)
          block_open = with_do(node.code, node.children).match?(BLOCK_OPENING)
        elsif block_open && node != NEWLINE
          emit_code("end")
          block_open = false
        end
        compile_node(node)
      end
      emit_code("end") if block_open
    end

    def compile_node(node)
      case node
      when NEWLINE
        @code << "\n" unless @newline_emitted
        @newline_emitted = false
      when Static then emit_static(node.text)
      when Text then emit_interpolated(node.text)
      when TextBlock then compile_children(node.children)
      when Tag then compile_tag(node)
      when Control then compile_control(node)
      when Output then compile_output(node)
      when InlineHtml
        emit_interpolated(node.text)
        compile_children(node.children)
      when Comment
        emit_static("<!--")
        compile_children(node.children)
        emit_static("-->")
      when Doctype then emit_static(doctype(node.type))
      when Embedded then compile_embedded(node)
      end
    end

    def compile_control(control)
      emit_code(with_do(control.code, control.children))
      compile_children(control.children)
    end

    def compile_output(output)
      code = with_do(output.code, output.children)
      unless code.match?(CAPTURED_OUTPUT)
        emit_output(code, output.escape)
        return compile_children(output.children)
      end

      result = new_variable
      emit_code("#{result} = #{code}")
      if @rails
        compile_children(output.children)
      else
        capture_into(new_variable) { compile_children(output.children) }
      end
      emit_code("end")
      emit_output(result, output.escape)
    end

    def with_do(code, children)
      (code.match?(BLOCK_SELF_OPENING) || AST.empty?(children)) ? code : "#{code} do"
    end

    def compile_tag(tag)
      return compile_dynamic_tag(tag) if tag.name == "*"

      closed = tag.content.nil? || (AST.renders_nothing?(tag.content) && (@xml || VOID_ELEMENTS.key?(tag.name)))
      emit_static("<#{tag.name}")
      compile_attributes(tag.attributes)
      emit_static((closed && @xml) ? " />" : ">")
      return if closed && tag.content.nil?

      compile_children(tag.content)
      emit_static("</#{tag.name}>") unless closed
    end

    def compile_dynamic_tag(tag)
      attributes = compile_runtime_attributes(tag.attributes)
      if tag.content.nil?
        emit_output("#{attributes}.build_tag", false)
      elsif AST.empty?(tag.content)
        emit_output(%(#{attributes}.build_tag("")), false)
        compile_children(tag.content)
      else
        content = new_variable
        capture_into(content) { compile_children(tag.content) }
        emit_output("#{attributes}.build_tag(#{content})", false)
      end
    end

    def compile_attributes(attributes)
      return if attributes.empty?
      return emit_output(compile_runtime_attributes(attributes), false) if attributes.any? { runtime_attribute?(_1) }

      if attributes.size > 1
        seen_names = {}
        attributes.each do |attribute|
          next if attribute.name == "class"
          raise Error, "Multiple #{attribute.name} attributes specified" if seen_names.key?(attribute.name)

          seen_names[attribute.name] = true
        end
      end

      # Every class value renders at the place of the first class attribute.
      class_attributes = nil
      attributes.each do |attribute|
        next compile_attribute(attribute) unless attribute.name == "class"
        next if class_attributes

        class_attributes = attributes.select { _1.name == "class" }
        compile_class_attribute(class_attributes.map { attribute_parts(_1) })
      end
    end

    def runtime_attribute?(attribute)
      attribute.is_a?(Splat) || (attribute.is_a?(CodeAttribute) && HYPHENATED_ATTRIBUTES.include?(attribute.name))
    end

    def compile_attribute(attribute)
      case attribute
      when BooleanAttribute then emit_boolean_attribute(attribute.name)
      when CodeAttribute then compile_code_attribute(attribute)
      else emit_attribute(attribute.name, attribute_parts(attribute))
      end
    end

    def compile_code_attribute(attribute)
      case attribute.code
      when "true" then emit_boolean_attribute(attribute.name)
      when "false", "nil" then nil
      else
        value = new_variable
        # A case on literals compiles to a jump table: no `==` call for the strings and numbers most values are.
        emit_code("case (#{value} = #{attribute.code})")
        emit_code("when true")
        emit_boolean_attribute(attribute.name)
        emit_code("when false, nil")
        emit_code("else")
        emit_attribute(attribute.name, [[:dynamic, value, attribute.escape]])
        emit_code("end")
      end
    end

    # Slim joins the non-empty values with spaces and drops an empty result. When the first value carries literal
    # text, as shortcuts always come first, the attribute is certain to render: each later value only needs its
    # separator, so nothing is joined at render time.
    def compile_class_attribute(values)
      values = values.reject { |parts| parts.all? { |kind, value| kind == :static && value.empty? } }
      if values.empty?
        nil
      elsif literal_text?(values.first)
        emit_static(' class="')
        values.each_with_index { |parts, index| emit_class_value(parts, separator: index > 0) }
        emit_static('"')
      else
        classes = new_variable
        expressions = values.map { string_expression(_1) }
        emit_code((values.size == 1) ? "#{classes} = #{expressions.first}" : "#{classes} = ::SlimX::Runtime.join_classes(#{expressions.join(", ")})")
        emit_code("unless #{classes}.empty?")
        emit_attribute("class", [[:raw, classes]])
        emit_code("end")
      end
    end

    def emit_class_value(parts, separator:)
      if literal_text?(parts)
        emit_static(" ") if separator
        emit_parts(parts)
      else
        value = new_variable
        emit_code("#{value} = #{string_expression(parts)}")
        emit_code("unless #{value}.empty?")
        emit_static(" ") if separator
        emit_output(value, false)
        emit_code("end")
      end
    end

    def literal_text?(parts)
      parts.any? { |kind, value| kind == :static && !value.empty? }
    end

    def compile_runtime_attributes(attributes)
      builder = new_variable
      emit_code("#{builder} = ::SlimX::Runtime::Attributes.new(#{@html_safe})")
      attributes.each do |attribute|
        case attribute
        when Splat
          emit_code("#{builder}.splat_attrs((#{attribute.code}))")
        when CodeAttribute
          emit_code("#{builder}.code_attr(#{attribute.name.inspect}, #{attribute.escape}, (#{attribute.code}))")
        else
          emit_code("#{builder}.attr(#{attribute.name.inspect}, #{string_expression(attribute_parts(attribute))})")
        end
      end
      builder
    end

    def attribute_parts(attribute)
      case attribute
      when StaticAttribute then [[:static, attribute.value]]
      when BooleanAttribute then []
      when CodeAttribute
        value = new_variable
        emit_code("#{value} = #{attribute.code}")
        [[:raw, "::SlimX::Runtime.class_value(#{value}, #{attribute.escape}, #{@html_safe})"]]
      when QuotedAttribute
        interpolation_parts(attribute.text).map do |kind, value, escape|
          (kind == :static && attribute.escape) ? [:static, ERB::Escape.html_escape(value)] : [kind, value, escape]
        end
      end
    end

    def emit_attribute(name, parts)
      emit_static(%( #{name}="))
      emit_parts(parts)
      emit_static('"')
    end

    def emit_boolean_attribute(name)
      emit_static(@xml ? %( #{name}="") : " #{name}")
    end

    def emit_parts(parts)
      parts.each do |kind, value, escape|
        case kind
        when :static then emit_static(value)
        when :dynamic then emit_output(value, escape)
        when :raw then emit_output(value, false)
        end
      end
    end

    def string_expression(parts)
      if parts.size == 1
        kind, value, escape = parts.first
        return "#{@escape_function}((#{value}))" if kind == :dynamic && escape
        return value if kind == :raw
      end

      literal = parts.map do |kind, value, escape|
        case kind
        when :static then value.inspect[1..-2]
        when :dynamic then escape ? "\#{#{@escape_function}((#{value}))}" : "\#{#{value}}"
        when :raw then "\#{#{value}}"
        end
      end
      %("#{literal.join}")
    end

    def emit_interpolated(text)
      emit_parts(interpolation_parts(text))
    end

    def interpolation_parts(text)
      return [[:static, text]] unless text.include?('#{')

      parts = []
      loop do
        case text
        when ESCAPED_INTERPOLATION
          parts << [:static, '#{']
        when INTERPOLATION
          code = $1
          escape = !code.match?(UNESCAPED_INTERPOLATION_CODE)
          parts << [:dynamic, escape ? code : code[1..-2], escape]
        when INTERPOLATION_FREE_TEXT
          parts << [:static, $&]
        end
        text = $'
        break if text.empty?
      end
      parts
    end

    def compile_embedded(embedded)
      case embedded.engine
      when "ruby"
        compile_ruby(embedded.children)
      when "javascript" then compile_tag(Tag.new("script", embedded.attributes, [TextBlock.new(embedded.children)]))
      when "css" then compile_tag(Tag.new("style", embedded.attributes, embedded.children))
      when "markdown" then compile_markdown(embedded.children)
      end
    end

    # Keeps every line of the block on its template line, blank lines included. The code must end with a
    # newline, as its last line may be a comment: when no blank line follows, that newline is the one of the
    # newline node that comes next.
    def compile_ruby(children)
      code = children.grep(Text).map(&:text).join
      trailing_newline_count = children.count(NEWLINE) - 1 - code.count("\n")
      @code << "\n"
      emit_code(code)
      @code << ("\n" * [trailing_newline_count, 1].max)
      @newline_emitted = trailing_newline_count.zero?
    end

    def compile_markdown(children)
      require "markly"

      placeholder = "%#{object_id.abs.to_s(36)}%"
      dynamic_parts = []
      markdown = children.grep(Text).flat_map { interpolation_parts(_1.text) }.map do |part|
        next part[1] if part.first == :static

        dynamic_parts << part
        "#{placeholder}#{dynamic_parts.size - 1}%"
      end
      Markly.render_html(markdown.join).split(/#{placeholder}(\d+)%/).each_with_index do |piece, index|
        index.odd? ? emit_parts([dynamic_parts[piece.to_i]]) : emit_static(piece)
      end
      children.count(NEWLINE).times { @code << "\n" }
    rescue LoadError
      raise Error, "Embedded engine markdown requires the markly gem"
    end

    def doctype(type)
      type = type.downcase
      if (xml = type.match(/\Axml(\s+(.+))?\z/))
        raise Error, "Invalid xml directive in html mode" unless @xml

        %(<?xml version="1.0" encoding="#{xml[2] || "utf-8"}" ?>)
      else
        DOCTYPES.fetch(@format)[type] || raise(Error, "Invalid doctype #{type}")
      end
    end

    def capture_into(variable)
      if @rails
        emit_code("#{variable} = capture do")
        yield
        emit_code("end")
      else
        outer_buffer = @buffer
        flush_static
        @buffer = StringBuffer.new(variable, @escape_function)
        emit_code(@buffer.open)
        yield
        emit_code(@buffer.close)
        @buffer = outer_buffer
      end
    end

    def emit_static(text)
      @static << text
    end

    def emit_output(code, escape)
      emit_code(escape ? @buffer.escaped(code) : @buffer.raw(code))
    end

    def emit_code(code)
      flush_static
      append(code)
    end

    def flush_static
      return if @static.empty?

      append(@buffer.static(@static))
      @static = +""
    end

    def append(code)
      @code << "; " unless @code.empty? || @code.end_with?("\n")
      @code << code
    end

    def new_variable
      "_slimx#{@variable_count += 1}"
    end

    class StringBuffer
      def initialize(name, escape_function)
        @name = name
        @escape_function = escape_function
      end

      def open = "#{@name} = +\"\""
      def close = @name
      def static(text) = "#{@name} << #{text.inspect}.freeze"
      def escaped(code) = "#{@name} << #{@escape_function}((#{code}))"
      def raw(code) = "#{@name} << (#{code}).to_s"
    end

    class OutputBuffer
      def open = "@output_buffer = output_buffer || ActionView::OutputBuffer.new"
      def close = "@output_buffer"
      def static(text) = "@output_buffer.safe_concat(#{text.inspect}.freeze)"
      def escaped(code) = "@output_buffer << (#{code})"
      def raw(code) = "@output_buffer.safe_concat((#{code}).to_s)"
    end
  end
end
