# frozen_string_literal: true

module SlimX
  class Railtie < Rails::Railtie
    initializer "slimx.register_template_handler" do
      ActiveSupport.on_load(:action_view) do
        require_relative "rails_handler"
        ActionView::Template.register_template_handler(:slim, SlimX::RailsHandler.new)
      end
    end
  end
end
