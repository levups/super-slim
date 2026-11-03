# frozen_string_literal: true

require_relative "lib/slimx/version"

Gem::Specification.new do |spec|
  spec.name = "slimx"
  spec.version = SlimX::VERSION
  spec.authors = ["Clément Joubert"]
  spec.summary = "Slim templates, rewritten: faster to compile and render, with a formatter and a linter"
  spec.description = "A Slim template engine rewritten from scratch, without Temple: same HTML as Slim 5, " \
                     "faster compilation and rendering with fewer allocations, a formatter that cannot change " \
                     "a page, a strict mode, and a linter with HTML and accessibility rules."
  spec.homepage = "https://github.com/next-gen-gems/slimx"
  spec.license = "MIT"
  spec.required_ruby_version = ">= 3.3"
  spec.metadata["source_code_uri"] = spec.homepage
  spec.metadata["changelog_uri"] = "#{spec.homepage}/blob/main/CHANGELOG.md"
  spec.metadata["rubygems_mfa_required"] = "true"
  spec.files = Dir["lib/**/*.rb", "exe/slimx", "LICENSE"]
  spec.bindir = "exe"
  spec.executables = ["slimx"]
  spec.require_paths = ["lib"]
end
