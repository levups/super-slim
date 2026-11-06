# frozen_string_literal: true

source "https://rubygems.org"

gemspec

group :development, :test do
  gem "actionpack", *@rails # gemfiles/rails_8_0.gemfile sets it
  gem "actionview", *@rails
  gem "benchmark-ips"
  gem "erubi"
  gem "haml"
  gem "herb"
  gem "markly"
  gem "minitest"
  gem "ostruct"
  gem "railties", *@rails
  gem "rake"
  gem "rubocop-performance", require: false
  gem "standard", require: false
  gem "slim", "5.2.2"
  gem "stackprof"
  gem "tilt"
end

group :development do
  gem "rouge", "5.1.0" # pinned: docs:highlight:check compares its output with the committed pages
end
