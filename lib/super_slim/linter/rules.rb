# frozen_string_literal: true

module SuperSlim
  class Linter
    module Rules
      # In the order of this file, which orders the offenses of one line: Module#constants has no order of its own.
      def self.all
        constants.sort_by { const_source_location(_1).last }.filter_map do |constant_name|
          rule = const_get(constant_name)
          rule if rule < Rule
        end
      end

      class Rule
        DEFAULTS = {enabled: true}.freeze

        def self.rule_name
          name.split("::").last
        end

        def initialize(options)
          @options = options
        end

        private

        attr_reader :options

        def offense(document, lineno, message)
          Offense.new(document.path, lineno, self.class.rule_name, message)
        end

        def each_tag(document, name = nil)
          document.each_tag do |tag, ancestors|
            yield tag, ancestors if name.nil? || tag.name == name
          end
        end

        def attribute_names(tag)
          tag.attributes.filter_map { _1.name unless _1.is_a?(AST::Splat) }
        end

        def each_line(document)
          document.lines.each.with_index(1)
        end

        def missing_attribute(document, tag_name, attribute_name, message)
          enum_for(:each_tag, document, tag_name).filter_map do |tag,|
            offense(document, document.line_of(tag), message) unless splat?(tag) || attribute_names(tag).include?(attribute_name)
          end
        end

        def splat?(tag)
          tag.attributes.any? { _1.is_a?(AST::Splat) }
        end

        # The value when it is written literally, nil when it is computed.
        def literal_value(attribute)
          case attribute
          when AST::StaticAttribute then attribute.value
          when AST::QuotedAttribute then attribute.text unless attribute.text.include?('#{')
          end
        end

        def literal_attributes(tag, name)
          tag.attributes.select { _1.respond_to?(:name) && _1.name == name && literal_value(_1) }
        end
      end

      # Layout: everything `super-slim fmt` rewrites.

      class Indentation < Rule
        def offenses(document, _source)
          document.outline.each_with_index.filter_map do |info, lineno|
            next unless info&.kind == :structure

            indent = document.lines[lineno - 1][/\A */].size
            expected = info.depth * Formatter::INDENT_WIDTH
            offense(document, lineno, "Indent with #{expected} spaces, not #{indent}") if indent != expected
          end
        end
      end

      class Tab < Rule
        def offenses(document, source)
          return [] unless source.include?("\t")

          each_line(document).filter_map { |line, lineno| offense(document, lineno, "Indent with spaces, not tabs") if line.match?(/\A *[\t ]*\t/) }
        end
      end

      class TrailingWhitespace < Rule
        # Matches wherever a line may end in whitespace, and a little more (a \r before \n): it only skips files.
        ANY_TRAILING_WHITESPACE = /[ \t\r\f\v](?=\r?\n|\z)/

        def offenses(document, source)
          return [] unless source.match?(ANY_TRAILING_WHITESPACE)

          each_line(document).filter_map do |line, lineno|
            next unless line.match?(/\s\z/)

            rendered = document.outline[lineno].text || document.outline[lineno].kind == :text
            offense(document, lineno, rendered ? "Trailing whitespace renders: write it with `'` or `>` instead" : "Remove trailing whitespace")
          end
        end
      end

      class EmptyLines < Rule
        def offenses(document, _source)
          previous_blank = true
          document.outline.each_with_index.filter_map do |info, lineno|
            next unless info

            blank = info.kind == :blank
            extra = blank && previous_blank
            previous_blank = blank
            offense(document, lineno, "Remove this extra empty line") if extra
          end
        end
      end

      class TrailingBlankLines < Rule
        def offenses(document, source)
          return [] if source.empty?
          return [offense(document, source.lines.size, "End the file with a newline")] unless source.end_with?("\n")

          source.end_with?("\n\n") ? [offense(document, source.lines.size, "Remove the empty lines at the end of the file")] : []
        end
      end

      class ControlStatementSpacing < Rule
        TAG_OUTPUT = /\A(\s*)(==?)(['<>]*)(\s*)(?=\S)/

        def offenses(document, _source)
          document.outline.each_with_index.filter_map do |info, lineno|
            next unless info

            line = document.lines[lineno - 1]
            if info.output_column
              line[info.output_column..] =~ TAG_OUTPUT
              offense(document, lineno, "Put a space before and after `#{$2}`") if $1.empty? || $4.empty?
            elsif info.kind == :structure
              case line.lstrip
              when /\A-(?=\S)/ then offense(document, lineno, "Put a space after `-`")
              when /\A((?>==?[<>]*))(?=\S)/ then offense(document, lineno, "Put a space after `#{$1}`")
              end
            end
          end
        end
      end

      class RedundantDiv < Rule
        def offenses(document, _source)
          document.outline.each_with_index.filter_map do |info, lineno|
            next unless info&.kind == :structure && document.lines[lineno - 1].lstrip.match?(Formatter::REDUNDANT_DIV)

            offense(document, lineno, "`div` is implied by the `.class` or `#id` shortcut")
          end
        end
      end

      # Slim-lint's rules on code and tags.

      class LineLength < Rule
        DEFAULTS = {enabled: true, max: 120}.freeze

        def offenses(document, _source)
          max = options[:max]
          each_line(document).filter_map { |line, lineno| offense(document, lineno, "Line is too long [#{line.length}/#{max}]") if line.length > max }
        end
      end

      class CommentControlStatement < Rule
        ALLOWED = /\A\s*#\s*(rubocop:|Template Dependency:)/

        def offenses(document, _source)
          document.enum_for(:each_node).filter_map do |node,|
            next unless node.is_a?(AST::Control) && node.code.match?(/\A\s*#/) && !node.code.match?(ALLOWED)

            offense(document, document.line_of(node), "Write comments with `/`, not `- #`: they cost nothing at render time")
          end
        end
      end

      class EmptyControlStatement < Rule
        def offenses(document, _source)
          document.enum_for(:each_node).filter_map do |node,|
            offense(document, document.line_of(node), "Remove this empty `-`") if node.is_a?(AST::Control) && node.code.strip.empty?
          end
        end
      end

      class ConsecutiveControlStatements < Rule
        DEFAULTS = {enabled: true, max: 2}.freeze

        def offenses(document, _source)
          sibling_lists = [document.nodes, *document.visits.filter_map { |node,| Document.children_of(node) }]
          sibling_lists.select! { |siblings| siblings.count { flat_control?(_1) } > options[:max] }
          sibling_lists.flat_map do |siblings|
            siblings.chunk_while { |control, following| flat_control?(control) && flat_control?(following) }
              .filter_map do
                next unless _1.size > options[:max] && flat_control?(_1.first)

                offense(document, document.line_of(_1.first), "Merge these #{_1.size} lines of Ruby into a `ruby:` block")
              end
          end
        end

        private

        def flat_control?(node)
          node.is_a?(AST::Control) && AST.empty?(node.children)
        end
      end

      class TagCase < Rule
        def offenses(document, _source)
          return [] if document.xml?

          document.enum_for(:each_node).filter_map do |node, ancestors|
            next unless node.is_a?(AST::Tag) && node.name.match?(/[A-Z]/)
            next if ancestors.any? { _1.is_a?(AST::Tag) && _1.name == "svg" }

            offense(document, document.line_of(node), "Write `#{node.name.downcase}` in lowercase")
          end
        end
      end

      class InstanceVariables < Rule
        INSTANCE_VARIABLE = /(?<![\w@])@[a-z_]\w*/

        def offenses(document, _source)
          return [] unless document.partial?

          document.enum_for(:each_node).filter_map do |node,|
            code = case node
            when AST::Control, AST::Output then node.code
            when AST::Tag then node.attributes.filter_map { _1.code if _1.respond_to?(:code) }.join(" ")
            end
            next unless code && (variable = code[INSTANCE_VARIABLE])

            offense(document, document.line_of(node), "Pass `#{variable}` to the partial as a local")
          end
        end
      end

      class StrictLocals < Rule
        DEFAULTS = {enabled: false}.freeze

        def offenses(document, _source)
          return [] if !document.partial? || document.lines.any? { _1.match?(%r{\A\s*/#\s*locals:}) }

          [offense(document, 1, "Declare the partial's locals: `/# locals: (name:)`")]
        end
      end

      # HTML and accessibility, after Herb, erb_lint and eslint-plugin-jsx-a11y.

      class DuplicateId < Rule
        def offenses(document, _source)
          branch_by_id = {}
          enum_for(:each_tag, document).filter_map do |tag, ancestors|
            branch = ancestors.reverse.find { _1.is_a?(AST::Control) }
            literal_attributes(tag, "id").filter_map do |attribute|
              id = literal_value(attribute)
              if branch_by_id.key?(id) && branch_by_id[id].equal?(branch)
                offense(document, document.line_of(tag), "The id `#{id}` is already used in this template")
              else
                branch_by_id[id] = branch
                nil
              end
            end
          end.flatten
        end
      end

      class ImageAlt < Rule
        def offenses(document, _source)
          missing_attribute(document, "img", "alt", 'Describe the image with `alt`, or mark it decorative with `alt=""`')
        end
      end

      class IframeTitle < Rule
        def offenses(document, _source)
          missing_attribute(document, "iframe", "title", "Name the frame with `title`")
        end
      end

      class AnchorHref < Rule
        def offenses(document, _source)
          missing_attribute(document, "a", "href", "A link without `href` is not a link: use a `button` for actions")
        end
      end

      class ButtonType < Rule
        DEFAULTS = {enabled: false}.freeze

        def offenses(document, _source)
          missing_attribute(document, "button", "type", 'Say what the button does with `type="button"` or `type="submit"`')
        end
      end

      class NestedLinks < Rule
        def offenses(document, _source)
          enum_for(:each_tag, document, "a").filter_map do |tag, ancestors|
            next unless ancestors.any? { _1.is_a?(AST::Tag) && _1.name == "a" }

            offense(document, document.line_of(tag), "Links cannot contain links")
          end
        end
      end

      class PositiveTabindex < Rule
        def offenses(document, _source)
          enum_for(:each_tag, document).flat_map do |tag,|
            literal_attributes(tag, "tabindex").filter_map do |attribute|
              next unless literal_value(attribute).to_i.positive?

              offense(document, document.line_of(tag), "A positive `tabindex` breaks the reading order: use 0 or -1")
            end
          end
        end
      end

      class BooleanAttributeValue < Rule
        BOOLEAN_ATTRIBUTES = %w[allowfullscreen async autofocus autoplay checked controls default defer disabled formnovalidate
          hidden inert ismap loop multiple muted nomodule novalidate open playsinline readonly required
          reversed selected].freeze

        def offenses(document, _source)
          enum_for(:each_tag, document).flat_map do |tag,|
            tag.attributes.filter_map do |attribute|
              next unless attribute.respond_to?(:name) && BOOLEAN_ATTRIBUTES.include?(attribute.name)
              next unless ["", attribute.name].include?(literal_value(attribute))

              offense(document, document.line_of(tag), "Write `#{attribute.name}=true`, or `#{attribute.name}` alone inside an attribute list")
            end
          end
        end
      end

      class AriaRole < Rule
        ROLES = %w[alert alertdialog application article banner blockquote button caption cell checkbox code columnheader
          combobox complementary contentinfo definition deletion dialog document emphasis feed figure form generic
          grid gridcell group heading img insertion link list listbox listitem log main marquee math menu menubar
          menuitem menuitemcheckbox menuitemradio meter navigation none note option paragraph presentation
          progressbar radio radiogroup region row rowgroup rowheader scrollbar search searchbox separator slider
          spinbutton status strong subscript superscript switch tab table tablist tabpanel term textbox time timer
          toolbar tooltip tree treegrid treeitem].freeze

        def offenses(document, _source)
          enum_for(:each_tag, document).flat_map do |tag,|
            literal_attributes(tag, "role").flat_map do |attribute|
              literal_value(attribute).split.filter_map do |role|
                next if ROLES.include?(role) || role.start_with?("doc-", "graphics-")

                offense(document, document.line_of(tag), "`#{role}` is not an ARIA role")
              end
            end
          end
        end
      end

      class AriaAttribute < Rule
        ATTRIBUTES = %w[activedescendant atomic autocomplete braillelabel brailleroledescription busy checked colcount
          colindex colindextext colspan controls current describedby description details disabled
          dropeffect errormessage expanded flowto grabbed haspopup hidden invalid keyshortcuts label
          labelledby level live modal multiline multiselectable orientation owns placeholder posinset
          pressed readonly relevant required roledescription rowcount rowindex rowindextext rowspan selected
          setsize sort valuemax valuemin valuenow valuetext].map { "aria-#{_1}" }.freeze

        def offenses(document, _source)
          enum_for(:each_tag, document).flat_map do |tag,|
            attribute_names(tag).filter_map do |name|
              next unless name.start_with?("aria-") && !ATTRIBUTES.include?(name)

              offense(document, document.line_of(tag), "`#{name}` is not an ARIA attribute")
            end
          end
        end
      end

      class DeprecatedClasses < Rule
        DEFAULTS = {enabled: true, classes: {}}.freeze

        def offenses(document, _source)
          replacement_by_class = options[:classes]
          return [] if replacement_by_class.empty?

          enum_for(:each_tag, document).flat_map do |tag,|
            literal_attributes(tag, "class").flat_map { literal_value(_1).split }.filter_map do |css_class|
              next unless replacement_by_class.key?(css_class)

              offense(document, document.line_of(tag), "`#{css_class}` is deprecated: use `#{replacement_by_class[css_class]}`")
            end
          end
        end
      end

      class InlineStyles < Rule
        DEFAULTS = {enabled: false}.freeze

        def offenses(document, _source)
          enum_for(:each_tag, document).filter_map do |tag,|
            offense(document, document.line_of(tag), "Move inline styles to a stylesheet") if literal_attributes(tag, "style").any?
          end
        end
      end

      # Ruby that a plainer line of Slim says better, after haml-lint.

      class UnnecessaryInterpolation < Rule
        LONE_INTERPOLATION = /\A#\{([^{}]+)\}\z/

        def offenses(document, _source)
          document.enum_for(:each_node).filter_map do |node, ancestors|
            next unless node.is_a?(AST::TextBlock)
            next unless (lineno = document.line_of(node) || document.line_of(ancestors.last))

            texts = node.children.grep(AST::Text)
            next unless texts.size == 1 && texts.first.text =~ LONE_INTERPOLATION

            offense(document, lineno, "Write `= #{$1.strip}` instead of interpolating it alone")
          end
        end
      end

      class UnnecessaryStringOutput < Rule
        PLAIN_STRING = /\A(["'])([^"'\\#&<>\s](?:[^"'\\#&<>]*[^"'\\#&<>\s])?)\1\z/
        # Text starting with one of these, written inline after a tag, reads as attributes or output: `span (note)`.
        READ_AS_SYNTAX_AFTER_TAG = /\A[(\[{=*\/]/

        def offenses(document, _source)
          document.enum_for(:each_node).filter_map do |node, ancestors|
            next unless node.is_a?(AST::Output) && AST.empty?(node.children) && node.code =~ PLAIN_STRING

            text = $2
            lineno = document.line_of(node)
            message = if text.match?(READ_AS_SYNTAX_AFTER_TAG) && ancestors.any? && document.line_of(ancestors.last) == lineno
              "Write the text `| #{text}` on its own line, under the tag: inline, it would read as attributes"
            else
              "Write the text `| #{text}` instead of outputting a string"
            end
            offense(document, lineno, message)
          end
        end
      end

      class Zwsp < Rule
        INVISIBLE = /[\u200B-\u200D\u2060\uFEFF]/
        # The zero-width joiner of 🐈‍⬛ or 👩🏻‍💻: between two pictographs, after an optional skin tone or emoji style.
        EMOJI_JOINER = /(?<=\p{Extended_Pictographic}|[\u{1F3FB}-\u{1F3FF}]|\uFE0F)\u200D(?=\p{Extended_Pictographic})/

        def offenses(document, source)
          return [] unless source.match?(INVISIBLE)

          each_line(document).filter_map do |line, lineno|
            line = line.delete_prefix("\uFEFF") if lineno == 1
            offense(document, lineno, "Remove the invisible zero-width character") if line.gsub(EMOJI_JOINER, "").match?(INVISIBLE)
          end
        end
      end
    end
  end
end
