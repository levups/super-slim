# frozen_string_literal: true

require "tilt"
require "super_slim"

module SuperSlim
  class Template < Tilt::Template
    def prepare
      @code = SuperSlim.compile(data, file: eval_file, **options)
    end

    def precompiled_template(_locals)
      @code
    end
  end
end

Tilt.register(SuperSlim::Template, "slim")
