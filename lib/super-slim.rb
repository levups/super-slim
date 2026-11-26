# frozen_string_literal: true

# Bundler requires a gem by its name: super-slim, then super/slim.
require_relative "super_slim"
# Again here: when the linter or the formatter was required before Rails, super_slim.rb ran without Rails.
require_relative "super_slim/railtie" if defined?(Rails::Railtie)
