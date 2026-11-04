# frozen_string_literal: true

require_relative "lib/slimx/version"

Gem::Specification.new do |spec|
  spec.name = "slimx"
  spec.version = SlimX::VERSION
  spec.authors = ["Level UP Solutions"]
  spec.summary = "Slim templates, rewritten: faster to compile and render, with a formatter and a linter"
  spec.description = "A Slim template engine rewritten from scratch, without Temple: same HTML as Slim 5, " \
                     "faster compilation and rendering with fewer allocations, a formatter that cannot change " \
                     "a page, a strict mode, a linter with HTML and accessibility rules, and a RuboCop plugin for the " \
                     "Ruby inside templates."
  spec.homepage = "https://github.com/next-gen-gems/slimx"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["documentation_uri"] = "https://next-gen-gems.github.io/slimx/"
  spec.metadata["bug_tracker_uri"] = "#{spec.homepage}/issues"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.metadata["default_lint_roller_plugin"] = "SlimX::RuboCop::Plugin"
  spec.files = Dir["lib/**/*.rb", "config/*.yml", "exe/slimx", "LICENSE", "LICENSE-slim", "README.md", "CHANGELOG.md"]
  spec.bindir = "exe"
  spec.executables = ["slimx"]
  spec.require_paths = ["lib"]

  # StringScanner#peek_byte arrived in strscan 3.1.1, after the one Ruby 3.3 ships.
  spec.add_dependency "strscan", ">= 3.1.1"
end
