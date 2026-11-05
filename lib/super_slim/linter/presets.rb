# frozen_string_literal: true

module SuperSlim
  class Linter
    # Bootstrap 4 classes and data attributes that Bootstrap 5.3 renamed or dropped.
    PRESETS = {
      "bootstrap5" => {
        "DeprecatedClasses" => {
          "alert-block" => "alert",
          "badge-pill" => "rounded-pill",
          "badge-*" => "text-bg-*",
          "bg-faded" => "bg-body-tertiary",
          "border-left*" => "border-start*",
          "border-right*" => "border-end*",
          "btn-block" => "w-100",
          "btn-default" => "btn-secondary",
          "card-deck" => "row",
          "close" => "btn-close",
          "custom-checkbox" => "form-check",
          "custom-control" => "form-check",
          "custom-file" => "form-control",
          "custom-radio" => "form-check",
          "custom-range" => "form-range",
          "custom-select" => "form-select",
          "custom-switch" => "form-switch",
          "dropdown-menu-left" => "dropdown-menu-start",
          "dropdown-menu-right" => "dropdown-menu-end",
          "embed-responsive" => "ratio",
          "float-left" => "float-start",
          "float-right" => "float-end",
          "font-italic" => "fst-italic",
          "font-weight-*" => "fw-*",
          "form-control-file" => "form-control",
          "form-group" => "mb-3",
          "form-inline" => "d-flex",
          "form-row" => "row",
          "input-group-append" => "input-group",
          "input-group-prepend" => "input-group",
          "jumbotron" => "p-5",
          "media" => "d-flex",
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
          "text-left" => "text-start",
          "text-monospace" => "font-monospace",
          "text-muted" => "text-body-secondary",
          "text-right" => "text-end",
          "thead-dark" => "table-dark",
          "thead-light" => "table-light"
        }.freeze,
        "DeprecatedAttributes" => %w[backdrop boundary container content delay dismiss html interval keyboard offset parent
          pause placement ride slide slide-to spy target toggle trigger wrap].to_h { ["data-#{_1}", "data-bs-#{_1}"] }.freeze
      }.freeze
    }.freeze
  end
end
