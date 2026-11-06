# frozen_string_literal: true

require "minitest/autorun"
require "open3"

class RenderingDependenciesTest < Minitest::Test
  def test_compiling_a_template_loads_no_prism
    template = "= format(\n    \"%s\",\n    \"alice\",\n  )\n- words = %w[\n    alice\n  ]\n"
    script = %(require "super_slim"; SuperSlim.compile(#{template.dump}); print defined?(Prism).inspect)
    output, status = Open3.capture2e(RbConfig.ruby, "-I", File.expand_path("../lib", __dir__), "-e", script)

    assert status.success?, output
    assert_equal "nil", output
  end
end
