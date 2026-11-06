# frozen_string_literal: true

require_relative "lib/super_slim/version"

Gem::Specification.new do |spec|
  spec.name = "super-slim"
  spec.version = SuperSlim::VERSION
  spec.authors = ["Level UP Solutions"]
  spec.summary = "A Slim template engine that compiles and renders faster, with a formatter and a linter"
  spec.description = "A Slim template engine written from scratch, without Temple. It renders the same HTML as " \
                     "Slim 5, compiles and renders faster with fewer allocations, and comes with a formatter " \
                     "that cannot change a page, a linter with HTML and accessibility rules, and a RuboCop " \
                     "plugin for the Ruby inside templates."
  spec.homepage = "https://github.com/levups/super-slim"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://levups.github.io/super-slim/"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["default_lint_roller_plugin"] = "SuperSlim::RuboCop::Plugin"
  spec.files = Dir["lib/**/*.rb", "config/*.yml", "exe/super-slim", "LICENSE", "LICENSE-slim", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["super-slim"]
  spec.require_paths = ["lib"]

  # StringScanner#peek_byte arrived in strscan 3.1.1, after the one Ruby 3.3 ships.
  spec.add_dependency "strscan", ">= 3.1.1"
end
