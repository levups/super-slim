# frozen_string_literal: true

require_relative "helper"

EXCLUDED = %w[test_commands test_erb_converter test_pretty test_thread_options test_splat_prefix_option].freeze
Dir[File.join(SLIM_TEST_DIRECTORY, "test_*.rb")].each do |path|
  require path unless EXCLUDED.include?(File.basename(path, ".rb"))
end

# Features SuperSlim drops on purpose, or whose output depends on the Markdown library Tilt happens to pick.
DROPPED_FEATURE_TESTS = %w[
  test_render_with_html_conditional_and_method_output test_render_with_html_conditional_and_tag
  test_render_with_custom_lambda_shortcut test_render_with_custom_lambda_shortcut_and_existing_class
  test_render_with_custom_lambda_shortcut_and_multiple_values test_render_with_existing_class_and_custom_lambda_shortcut
  test_wip_render_with_asciidoc test_render_with_markdown test_registered_extension
  test_single_tab1_expansion test_multi_tab1_expansion
].freeze
# Slim reports `= unknown_ruby_method` on line 7 while it sits on line 6, one line after a ruby: block; the test
# pins that drift. SuperSlim keeps every line of a ruby: block on its template line.
SLIM_LINE_DRIFT_TESTS = %w[test_embedded_ruby1].freeze
# Checks Slim's own class, which Temple gives its MIME type on the first template it prepares: the test passed or
# failed depending on the seed.
SLIM_ORDER_DEPENDENT_TESTS = %w[test_default_mime_type].freeze
Minitest::Test.prepend(Module.new do
  def before_setup
    super
    skip "Dropped from SuperSlim" if DROPPED_FEATURE_TESTS.include?(name)
    skip "Pins a line drift of Slim that SuperSlim fixes" if SLIM_LINE_DRIFT_TESTS.include?(name)
    skip "Tests Slim's class, and only after another test" if SLIM_ORDER_DEPENDENT_TESTS.include?(name)
  end
end)
