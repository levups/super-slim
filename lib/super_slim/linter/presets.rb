# frozen_string_literal: true

module SuperSlim
  class Linter
    # Bootstrap 4 classes and data attributes that Bootstrap 5.3 renamed, keyed by rule then by option.
    PRESETS = {
      "bootstrap5" => {
        "DeprecatedClasses" => {
          classes: {
            "badge-pill" => "rounded-pill",
            "badge-*" => "text-bg-*",
            "border-left*" => "border-start*",
            "border-right*" => "border-end*",
            "btn-block" => "w-100",
            "card-deck" => "row",
            "close" => "btn-close",
            "custom-checkbox" => "form-check",
            "custom-control" => "form-check",
            "custom-control-inline" => "form-check-inline",
            "custom-control-input" => "form-check-input",
            "custom-control-label" => "form-check-label",
            "custom-file" => "form-control",
            "custom-radio" => "form-check",
            "custom-range" => "form-range",
            "custom-select" => "form-select",
            "custom-select-lg" => "form-select-lg",
            "custom-select-sm" => "form-select-sm",
            "custom-switch" => "form-switch",
            "embed-responsive" => "ratio",
            "embed-responsive-1by1" => "ratio-1x1",
            "embed-responsive-4by3" => "ratio-4x3",
            "embed-responsive-16by9" => "ratio-16x9",
            "embed-responsive-21by9" => "ratio-21x9",
            "font-italic" => "fst-italic",
            "font-weight-*" => "fw-*",
            "form-control-file" => "form-control",
            "form-group" => "mb-3",
            "form-inline" => "d-flex",
            "form-row" => "row",
            "jumbotron" => "p-5",
            "media" => "d-flex",
            "media-body" => "flex-grow-1",
            "ml-*" => "ms-*",
            "mr-*" => "me-*",
            "no-gutters" => "g-0",
            "pl-*" => "ps-*",
            "pr-*" => "pe-*",
            "pre-scrollable" => "overflow-y-scroll",
            "rounded-left*" => "rounded-start*",
            "rounded-lg" => "rounded-3",
            "rounded-right*" => "rounded-end*",
            "rounded-sm" => "rounded-1",
            "sr-only" => "visually-hidden",
            "sr-only-focusable" => "visually-hidden-focusable",
            "text-monospace" => "font-monospace",
            "text-muted" => "text-body-secondary",
            "thead-dark" => "table-dark",
            "thead-light" => "table-light",
            **%w[float text dropdown-menu].product(["", "-sm", "-md", "-lg", "-xl"]).flat_map do |utility, breakpoint|
              [["#{utility}#{breakpoint}-left", "#{utility}#{breakpoint}-start"], ["#{utility}#{breakpoint}-right", "#{utility}#{breakpoint}-end"]]
            end.to_h
          }.freeze
        },
        "DeprecatedAttributes" => {
          attributes: %w[animation autohide backdrop boundary container content delay dismiss display fallback-placement flip
            html interval keyboard offset parent pause placement reference ride selector slide slide-to spy target template
            toggle touch trigger wrap].to_h { ["data-#{_1}", "data-bs-#{_1}"] }.freeze
        }
      }.freeze
    }.freeze
  end
end
