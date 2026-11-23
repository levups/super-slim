# frozen_string_literal: true

require "erb/escape"

module SuperSlim
  module Runtime
    module_function

    def escape_html(value)
      ERB::Escape.html_escape(value.to_s)
    end

    # Only Rails defines html_safe? on every object: where String alone does, a number or nil has none and is escaped.
    # Rescued rather than checked, so that Rails pays nothing; those other setups pay an exception per such value.
    def escape_html_safe(value)
      string = value.to_s
      (string.html_safe? || value.html_safe?) ? string : ERB::Escape.html_escape(string)
    rescue NoMethodError => error
      # Raised by to_s, by a String without html_safe?, or inside the value's own html_safe?: not ours to handle.
      raise unless string && !value.equal?(string) && missing_html_safe?(error, value)

      ERB::Escape.html_escape(string)
    end

    def missing_html_safe?(error, value)
      receiver = begin
        error.receiver
      rescue ArgumentError # A NoMethodError raised by hand may have none.
      end
      error.name == :html_safe? && receiver.equal?(value) && !value.respond_to?(:html_safe?, true)
    end

    def class_value(value, escape, html_safe)
      if value.is_a?(Array)
        # `flatten` returns a new array: changing it in place spares one more.
        classes = value.flatten.map!(&:to_s)
        classes.reject!(&:empty?)
        value = classes.join(" ")
      end
      return value.to_s unless escape

      html_safe ? escape_html_safe(value) : escape_html(value)
    end

    def join_classes(*values)
      values.reject!(&:empty?)
      values.join(" ")
    end

    # Attributes only known at render time: splats (`*hash`), `data=`/`aria=` hashes and dynamic tags (`*{tag: "a"}`).
    # A hash of each attribute's rendered value by name, in the order they render: one object per tag.
    class Attributes < Hash
      # Slim lets tabs and line breaks through: they end a name, so `data: {"x\tonclick" => code}` set onclick.
      INVALID_NAME = /[[:cntrl:] "'>\/=]/
      # Read after escaping, which turns markup into entities: `&` is refused with the rest.
      VALID_TAG = /\A[a-zA-Z][^[:cntrl:] "'&<>\/=]*\z/
      HYPHENATED = %w[data aria].freeze
      # Far deeper than any page needs, and short of the stack a hash referring to itself would exhaust.
      MAX_HYPHENATED_DEPTH = 100

      # Names are checked unless the compiler already found them valid: those from render-time data always are.
      def code_attr(name, escape, value, check = true)
        if name == "class"
          value = value.is_a?(Array) ? value.join(" ") : value.to_s
          attr(name, escape(escape, value), false) unless value.empty?
        elsif HYPHENATED.include?(name) && value.is_a?(Hash)
          hyphenated_attr(name, escape, value)
        elsif value != false && !value.nil?
          attr(name, escape(escape, value), check)
        end
      end

      def splat_attrs(splat)
        splat.each { |name, value| code_attr(name.is_a?(Symbol) ? name.name : name.to_s, true, value) }
      end

      def attr(name, value, check = true)
        raise InvalidAttributeNameError, "Invalid attribute name '#{name}' was rendered" if check && (name.empty? || name.match?(INVALID_NAME))

        if !key?(name)
          self[name] = value
        elsif name == "class"
          self[name] = "#{self[name]} #{value}"
        else
          raise "Multiple #{name} attributes specified"
        end
      end

      def build_tag(content = nil)
        tag = delete("tag").to_s
        tag = "div" if tag.empty?
        raise InvalidTagNameError, "Invalid tag name '#{tag}' was rendered" unless tag.match?(VALID_TAG)
        content ? "<#{tag}#{self}>#{content}</#{tag}>" : "<#{tag}#{self} />"
      end

      def to_s
        html = +""
        each do |name, value|
          html << " " << name
          html << %(=") << value.to_s << %(") unless value == true
        end
        html
      end

      private

      def hyphenated_attr(name, escape, value, depth = 0)
        if value.is_a?(Hash)
          raise Error, "A data or aria hash is nested more than #{MAX_HYPHENATED_DEPTH} levels deep" if depth > MAX_HYPHENATED_DEPTH

          value.each { |key, nested_value| hyphenated_attr("#{name}-#{key}", escape, nested_value, depth + 1) }
        else
          attr(name, escape(escape, value))
        end
      end

      def escape(escape, value)
        (!escape || value == true) ? value : Runtime.escape_html(value)
      end
    end

    # Values that are `html_safe?` render as they are.
    class HtmlSafeAttributes < Attributes
      private

      def escape(escape, value)
        (!escape || value == true) ? value : Runtime.escape_html_safe(value)
      end
    end
  end
end
