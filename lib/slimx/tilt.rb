# frozen_string_literal: true

require "tilt"
require_relative "../slimx"

module SlimX
  class Template < Tilt::Template
    def prepare
      @code = SlimX.compile(data, file: eval_file, **options)
    end

    def precompiled_template(_locals)
      @code
    end
  end
end

Tilt.register(SlimX::Template, "slim")
