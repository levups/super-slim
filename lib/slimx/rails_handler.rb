# frozen_string_literal: true

module SlimX
  class RailsHandler
    def call(template, source = nil)
      SlimX.compile(
        source || template.source,
        file: template.identifier,
        format: xml?(template) ? :xml : :html,
        rails: true,
        **annotations(template)
      )
    end

    def supports_streaming?
      true
    end

    private

    def xml?(template)
      template.format && ::Mime[template.format].to_s.end_with?("xml")
    end

    def annotations(template)
      return {} unless ActionView::Base.annotate_rendered_view_with_filenames && template.format == :html

      {preamble: "<!-- BEGIN #{template.short_identifier} -->\n", postamble: "<!-- END #{template.short_identifier} -->\n"}
    end
  end
end
