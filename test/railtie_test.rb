# frozen_string_literal: true

require "json"
require "minitest/autorun"
require "open3"

class RailtieTest < Minitest::Test
  SLIM_PARTIAL = <<~SLIM
    /# Template Dependency: orders/total
    - cache order do
      = render "orders/header"
      == render partial: "orders/line", collection: order.lines
      .comments = render @comments
      p Never render text
  SLIM
  SLIM_DEPENDENCIES = %w[comments/comment orders/header orders/line orders/total].freeze

  def test_slim_cache_digests_follow_the_partials_rendered_inside
    assert_equal SLIM_DEPENDENCIES, slim_partial_dependencies.sort
  end

  def test_slim_cache_digests_follow_the_partials_when_action_view_loads_first
    assert_equal SLIM_DEPENDENCIES, slim_partial_dependencies(action_view_loaded_first: true).sort
  end

  private

  # A process of its own: the Railtie registers the handler and the tracker for the whole process.
  def slim_partial_dependencies(action_view_loaded_first: false)
    script = <<~RUBY
      require "rails"
      require "action_view"
      require "super_slim"
      ActionView::Base if #{action_view_loaded_first}
      SuperSlim::Railtie.instance.run_initializers
      ActionView::Base
      handler = ActionView::Template.handler_for_extension(:slim)
      template = ActionView::Template.new(#{SLIM_PARTIAL.dump}, "orders/_order", handler, locals: [])
      print JSON.generate(ActionView::DependencyTracker.find_dependencies("orders/_order", template))
    RUBY
    output, errors, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-e", script)

    assert status.success?, errors
    JSON.parse(output)
  end
end
