# frozen_string_literal: true

require "prism"

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
        GLOB_FLAGS = File::FNM_PATHNAME | File::FNM_EXTGLOB | File::FNM_DOTMATCH

        def self.rule_name
          @rule_name ||= name.split("::").last
        end

        def initialize(options)
          @options = options
        end

        def applies_to?(path)
          included = options[:include].nil? || Array(options[:include]).any? { File.fnmatch?(_1, path, GLOB_FLAGS) }
          included && Array(options[:exclude]).none? { File.fnmatch?(_1, path, GLOB_FLAGS) }
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

        # Text nodes carry no line of their own: they take the line of the closest node that does.
        def line_near(document, node, ancestors)
          document.line_of(node) || document.line_of(ancestors.located)
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

        INTERPOLATION = /#\{\{?([^{}]*)\}?\}/

        # Each piece of Ruby in the template, with the line it starts on: `-` and `=` lines, attribute values, splats,
        # `ruby:` blocks, and the interpolations of text and quoted attributes.
        def each_ruby(document)
          document.each_node do |node, ancestors|
            case node
            when AST::Control, AST::Output then yield node.code, document.line_of(node)
            when AST::Tag
              node.attributes.each do |attribute|
                case attribute
                when AST::CodeAttribute, AST::Splat then yield attribute.code, document.line_of(node)
                when AST::QuotedAttribute then attribute.text.scan(INTERPOLATION) { yield $1, document.line_of(node) }
                end
              end
            when AST::Embedded
              next unless node.engine == "ruby"

              yield node.children.grep(AST::Text).map(&:text).join, document.line_of(node) + 1
            when AST::Text
              next if ancestors.last.is_a?(AST::Embedded) && ancestors.last.engine == "ruby"

              node.text.scan(INTERPOLATION) { yield $1, line_near(document, node, ancestors) }
            end
          end
        end

        # Prism reads a `- if` or `- each do` line without its `end`, as it reads code with errors: the tree it gives
        # holds the calls written.
        def each_prism_node(code_or_node)
          stack = [code_or_node.is_a?(String) ? Prism.parse(code_or_node).value : code_or_node]
          until stack.empty?
            node = stack.pop
            yield node
            stack.concat(node.compact_child_nodes)
          end
        end
      end

      # Layout: everything `super-slim format` rewrites.

      class Indentation < Rule
        def offenses(document, _source)
          document.outline.each_with_index.filter_map do |info, lineno|
            next unless info&.kind == :structure

            line = document.lines[lineno - 1]
            indent = 0
            indent += 1 while line.getbyte(indent) == Parser::SPACE_BYTE
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
        def offenses(document, source)
          # Whitespace ending a line is in one of these, as are a few more files (a \r anywhere): they only skip files.
          # A string search is faster than any regexp here.
          return [] unless source.include?(" \n") || source.include?("\t\n") || source.include?("\r") || source.include?("\f") ||
            source.include?("\v") || source.end_with?(" ", "\t")

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
        # [\s\0]* is what String#lstrip strips.
        UNSPACED_CONTROL = /\A[\s\0]*-(?=\S)/
        UNSPACED_OUTPUT = /\A[\s\0]*((?>==?[<>]*))(?=\S)/

        def offenses(document, _source)
          document.outline.each_with_index.filter_map do |info, lineno|
            next unless info

            line = document.lines[lineno - 1]
            if info.output_column
              next unless line[info.output_column..] =~ TAG_OUTPUT

              offense(document, lineno, "Put a space before and after `#{$2}`") if $1.empty? || $4.empty?
            elsif info.kind == :structure
              case line
              when UNSPACED_CONTROL then offense(document, lineno, "Put a space after `-`")
              when UNSPACED_OUTPUT then offense(document, lineno, "Put a space after `#{$1}`")
              end
            end
          end
        end
      end

      class RedundantDiv < Rule
        # [\s\0]* is what String#lstrip strips.
        REDUNDANT_DIV = /\A[\s\0]*div(?=[.#][\p{Word}-])/

        def offenses(document, _source)
          document.outline.each_with_index.filter_map do |info, lineno|
            next unless info&.kind == :structure && document.lines[lineno - 1].match?(REDUNDANT_DIV)

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
            siblings.chunk_while { |node, following| flat_control?(node) && flat_control?(following) }
              .filter_map do |run|
                next unless run.size > options[:max] && flat_control?(run.first)

                offense(document, document.line_of(run.first), "Merge these #{run.size} lines of Ruby into a `ruby:` block")
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
            next if ancestors.inside_svg

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

      class UnusedLocals < Rule
        SIGNATURE = %r{\A\s*/#\s*locals:\s*(\(.*\))\s*\z}

        def offenses(document, _source)
          return [] unless (lineno = document.lines.index { _1.match?(SIGNATURE) })

          definition = Prism.parse("def _#{document.lines[lineno][SIGNATURE, 1]}; end").value.statements&.body&.first
          return [] unless definition.is_a?(Prism::DefNode) && definition.parameters

          declared = definition.parameters.keywords.map(&:name)
          # A default can read another local: `(post:, title: post.title)`.
          read = Set.new
          definition.parameters.keywords.each { read.merge(names_read(_1.value)) if _1.respond_to?(:value) }
          each_ruby(document) { |code,| read.merge(names_read(code)) }
          return [] if read.include?(:local_assigns)

          (declared - read.to_a).map { offense(document, lineno + 1, "The local `#{_1}` is declared but never read") }
        end

        private

        # A partial reads its locals as methods without receiver nor arguments, the shorthand `post:` included, or as
        # variables once code has assigned them.
        def names_read(code_or_node)
          names = Set.new
          each_prism_node(code_or_node) do |node|
            case node
            when Prism::LocalVariableReadNode then names << node.name
            when Prism::CallNode then names << node.name if node.receiver.nil? && node.arguments.nil?
            end
          end
          names
        end
      end

      # HTML and accessibility, after Herb, erb_lint and eslint-plugin-jsx-a11y.

      class DuplicateId < Rule
        def offenses(document, _source)
          branch_by_id = {}
          enum_for(:each_tag, document).flat_map do |tag, ancestors|
            branch = ancestors.control
            literal_attributes(tag, "id").filter_map do |attribute|
              id = literal_value(attribute)
              if branch_by_id.key?(id) && branch_by_id[id].equal?(branch)
                offense(document, document.line_of(tag), "The id `#{id}` is already used in this template")
              else
                branch_by_id[id] = branch
                nil
              end
            end
          end
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

      # After eslint-plugin-jsx-a11y's anchor-is-valid: `href="#"` and `javascript:` only stand in for a click handler.
      class AnchorHref < Rule
        PLACEHOLDER = /\A\s*(?:#|javascript:.*)\z/im

        def offenses(document, _source)
          placeholders = enum_for(:each_tag, document, "a").flat_map do |tag,|
            literal_attributes(tag, "href").filter_map do |attribute|
              next unless (href = literal_value(attribute)).match?(PLACEHOLDER)

              target = href.strip.start_with?("#") ? '`href="#"`' : "A `javascript:` URL"
              offense(document, document.line_of(tag), "#{target} goes nowhere: use a `button` for actions")
            end
          end
          missing_attribute(document, "a", "href", "A link without `href` is not a link: use a `button` for actions") + placeholders
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
            next unless ancestors.inside_link

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

      # Slim renders `aria-atomic=true` as a bare `aria-atomic` and drops `aria-hidden=false`: ARIA reads the string.
      class AriaBooleanValue < Rule
        BOOLEAN_CODES = %w[true false].freeze

        def offenses(document, _source)
          enum_for(:each_tag, document).flat_map do |tag,|
            tag.attributes.filter_map do |attribute|
              next unless attribute.is_a?(AST::CodeAttribute) && attribute.name.start_with?("aria-")
              next unless BOOLEAN_CODES.include?(value = attribute.code.strip)

              offense(document, document.line_of(tag), "Write `#{attribute.name}=\"#{value}\"`: Slim renders `#{attribute.name}=#{value}` #{(value == "true") ? "without a value" : "as no attribute at all"}")
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

        # A key ending in `*` matches every class with that prefix, and carries the rest over: `ml-*: ms-*`.
        def initialize(options)
          super
          prefixed, exact = Hash(options[:classes]).partition { |deprecated,| deprecated.end_with?("*") }
          @replacement_by_class = exact.to_h
          # The longest prefix wins: `badge-light-*` over `badge-*`.
          @prefixed_replacements = prefixed.map { |deprecated, replacement| [deprecated.delete_suffix("*"), replacement] }.sort_by { -_1.first.size }
        end

        def offenses(document, _source)
          return [] if @replacement_by_class.empty? && @prefixed_replacements.empty?

          enum_for(:each_tag, document).flat_map do |tag,|
            literal_attributes(tag, "class").flat_map { literal_value(_1).split }.filter_map do |css_class|
              next unless (replacement = replacement_of(css_class))

              offense(document, document.line_of(tag), "`#{css_class}` is deprecated: use `#{replacement}`")
            end
          end
        end

        private

        def replacement_of(css_class)
          return @replacement_by_class[css_class] if @replacement_by_class.key?(css_class)

          prefix, replacement = @prefixed_replacements.find { |prefix,| css_class.start_with?(prefix) }
          replacement&.sub("*", css_class.delete_prefix(prefix))
        end
      end

      class DeprecatedAttributes < Rule
        DEFAULTS = {enabled: true, attributes: {}}.freeze

        def initialize(options)
          super
          @replacement_by_attribute = Hash(options[:attributes])
        end

        def offenses(document, _source)
          return [] if @replacement_by_attribute.empty?

          enum_for(:each_tag, document).flat_map do |tag,|
            attribute_names(tag).filter_map do |name|
              next unless (replacement = @replacement_by_attribute[name])

              offense(document, document.line_of(tag), "`#{name}` is deprecated: use `#{replacement}`")
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

      class InlineEventHandlers < Rule
        DEFAULTS = {enabled: false}.freeze
        HANDLER = /\Aon[a-z]+\z/

        def offenses(document, _source)
          enum_for(:each_tag, document).flat_map do |tag,|
            attribute_names(tag).grep(HANDLER).map do |name|
              offense(document, document.line_of(tag), "Move the `#{name}` handler to JavaScript: a strict Content Security Policy blocks it")
            end
          end
        end
      end

      class UnescapedOutput < Rule
        DEFAULTS = {enabled: false}.freeze
        SKIPS_ESCAPING = /\.html_safe\b|(?<![\w.:@])raw[ (]/
        UNESCAPED_INTERPOLATION = /#\{\{/
        MESSAGE = "skips HTML escaping: output with `=`, or render HTML from a translation key ending in `_html`"

        def offenses(document, _source)
          document.enum_for(:each_node).flat_map do |node, ancestors|
            reasons_of(node).map { offense(document, line_near(document, node, ancestors), "#{_1} #{MESSAGE}") }
          end
        end

        private

        def reasons_of(node)
          case node
          when AST::Output then [*("`==`" unless node.escape), *code_reason(node.code)]
          when AST::Control then code_reason(node.code)
          when AST::Tag then node.attributes.flat_map { attribute_reasons(_1) }
          when AST::Text then node.text.match?(UNESCAPED_INTERPOLATION) ? ["`\#{{}}`"] : []
          when AST::Embedded then (node.engine == "ruby") ? code_reason(node.children.grep(AST::Text).map(&:text).join("\n")) : []
          else []
          end
        end

        def attribute_reasons(attribute)
          case attribute
          when AST::CodeAttribute then [*("`==`" unless attribute.escape), *code_reason(attribute.code)]
          when AST::Splat then code_reason(attribute.code)
          else []
          end
        end

        def code_reason(code)
          return [] unless (call = code[SKIPS_ESCAPING])

          [call.start_with?(".") ? "`html_safe`" : "`raw`"]
        end
      end

      class EmbeddedEngines < Rule
        DEFAULTS = {enabled: false, forbidden_engines: []}.freeze

        def offenses(document, _source)
          forbidden_engines = options[:forbidden_engines]
          document.enum_for(:each_node).filter_map do |node,|
            next unless node.is_a?(AST::Embedded) && forbidden_engines.include?(node.engine)

            offense(document, document.line_of(node), "The `#{node.engine}:` engine is forbidden here: move this code to a file of its own")
          end
        end
      end

      class HardcodedText < Rule
        DEFAULTS = {enabled: false}.freeze
        NOT_WORDS = /#\{\{?[^{}]*\}?\}|&(?:[a-z]+|#\d+|#x\h+);|<!\[CDATA\[|\]\]>|<[^<>]+>/i
        EXCERPT_LENGTH = 40

        def offenses(document, _source)
          document.enum_for(:each_node).filter_map do |node, ancestors|
            next unless node.is_a?(AST::TextBlock) && !ancestors.inside_comment

            text = node.children.grep(AST::Text).map(&:text).join(" ").gsub(/\s+/, " ").strip
            next unless text.gsub(NOT_WORDS, "").match?(/\p{L}/)

            excerpt = (text.length > EXCERPT_LENGTH) ? "#{text[0, EXCERPT_LENGTH]}…" : text
            offense(document, line_near(document, node, ancestors), "Translate `#{excerpt}` instead of writing it in the template")
          end
        end
      end

      # Matched by method name: an off-by-default rule, since a few of these also run on arrays.
      class DatabaseQueries < Rule
        DEFAULTS = {enabled: false}.freeze
        QUERY_METHODS = %i[where find_by find_by! pluck pick exists? find_each find_in_batches in_batches].to_set.freeze
        # Called on a constant, these read a model's table: `Tag.order(:name)`.
        MODEL_METHODS = %i[all order find first last count limit includes joins sum minimum maximum].to_set.freeze

        def offenses(document, _source)
          calls_by_lineno = Hash.new { |hash, lineno| hash[lineno] = [] }
          each_ruby(document) do |code, lineno|
            next unless lineno

            each_prism_node(code) do |node|
              next unless node.is_a?(Prism::CallNode) && (call = query(node))

              calls_by_lineno[lineno + node.location.start_line - 1] << [node.message_loc.start_offset, call]
            end
          end
          # One offense a line, its calls in the order they are written: the tree is walked from the outermost.
          calls_by_lineno.keys.sort!.map! do |lineno|
            calls = calls_by_lineno[lineno].sort.map!(&:last).uniq
            offense(document, lineno, "#{calls.map { "`#{_1}`" }.join(", ")} #{(calls.size == 1) ? "queries" : "query"} " \
              "the database from the template: load the records in the controller")
          end
        end

        private

        def query(node)
          return unless node.receiver

          if node.receiver.is_a?(Prism::ConstantReadNode) || node.receiver.is_a?(Prism::ConstantPathNode)
            "#{node.receiver.slice}.#{node.name}" if MODEL_METHODS.include?(node.name) || QUERY_METHODS.include?(node.name)
          elsif QUERY_METHODS.include?(node.name)
            node.name.to_s
          end
        end
      end

      # Brakeman parses views with Slim, which refuses these lines: it reports the template and checks nothing in it.
      class SlimSyntax < Rule
        MESSAGE = "Slim, and so Brakeman, cannot read"

        def offenses(document, _source)
          document.enum_for(:each_node).filter_map do |node, ancestors|
            next unless node.is_a?(AST::Output) || node.is_a?(AST::Control)
            next unless (reason = reason_of(node.code))

            offense(document, line_near(document, node, ancestors), "#{MESSAGE} #{reason}")
          end
        end

        private

        def reason_of(code)
          if !Parser.slim_continuation?(code.split("\n"))
            "code continued after an opening bracket: end each line but the last with a comma"
          elsif Parser::RubyBrackets.code_comment_offset(code)
            "a comment after code: move it to a line of its own"
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
            message = if text.match?(READ_AS_SYNTAX_AFTER_TAG) && ancestors.last && document.line_of(ancestors.last) == lineno
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
          return [] if source.ascii_only? || !source.match?(INVISIBLE)

          each_line(document).filter_map do |line, lineno|
            line = line.delete_prefix("\uFEFF") if lineno == 1
            offense(document, lineno, "Remove the invisible zero-width character") if line.gsub(EMOJI_JOINER, "").match?(INVISIBLE)
          end
        end
      end
    end
  end
end
