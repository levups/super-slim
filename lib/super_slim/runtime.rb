# frozen_string_literal: true

require "erb/escape"

module SuperSlim
  module Runtime
    module_function

    def escape_html(value)
      ERB::Escape.html_escape(value.to_s)
    end

    def escape_html_safe(value)
      string = value.to_s
      (string.html_safe? || value.html_safe?) ? string : ERB::Escape.html_escape(string)
    end

    def class_value(value, escape, html_safe)
      if value.is_a?(Array)
        value = value.flatten.filter_map do |element|
          string = element.to_s
          string unless string.empty?
        end.join(" ")
      end
      return value.to_s unless escape

      html_safe ? escape_html_safe(value) : escape_html(value)
    end

    def join_classes(*values)
      values.reject(&:empty?).join(" ")
    end

    # Attributes only known at render time: splats (`*hash`), `data=`/`aria=` hashes and dynamic tags (`*{tag: "a"}`).
    class Attributes
      INVALID_NAME = /[ \0"'>\/=]/
      HYPHENATED = %w[data aria].freeze

      def initialize(html_safe)
        @html_safe = html_safe
        @value_by_name = {}
      end

      def code_attr(name, escape, value)
        if name == "class"
          value = value.is_a?(Array) ? value.join(" ") : value.to_s
          attr(name, escape(escape, value)) unless value.empty?
        elsif HYPHENATED.include?(name) && value.is_a?(Hash)
          hyphenated_attr(name, escape, value)
        elsif value != false && !value.nil?
          attr(name, escape(escape, value))
        end
      end

      def splat_attrs(splat)
        splat.each { |name, value| code_attr(name.is_a?(Symbol) ? name.name : name.to_s, true, value) }
      end

      def attr(name, value)
        raise InvalidAttributeNameError, "Invalid attribute name '#{name}' was rendered" if name.match?(INVALID_NAME)

        if !@value_by_name.key?(name)
          @value_by_name[name] = value
        elsif name == "class"
          @value_by_name[name] = "#{@value_by_name[name]} #{value}"
        else
          raise "Multiple #{name} attributes specified"
        end
      end

      def build_tag(content = nil)
        tag = @value_by_name.delete("tag").to_s
        tag = "div" if tag.empty?
        content ? "<#{tag}#{self}>#{content}</#{tag}>" : "<#{tag}#{self} />"
      end

      def to_s
        html = +""
        @value_by_name.each do |name, value|
          html << " " << name
          html << %(=") << value.to_s << %(") unless value == true
        end
        html
      end

      private

      def hyphenated_attr(name, escape, value)
        if value.is_a?(Hash)
          value.each { |key, nested_value| hyphenated_attr("#{name}-#{key}", escape, nested_value) }
        else
          attr(name, escape(escape, value))
        end
      end

      def escape(escape, value)
        return value if !escape || value == true

        @html_safe ? Runtime.escape_html_safe(value) : Runtime.escape_html(value)
      end
    end
  end
end
