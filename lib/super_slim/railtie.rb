# frozen_string_literal: true

module SuperSlim
  class Railtie < Rails::Railtie
    initializer "super_slim.register_template_handler" do
      ActiveSupport.on_load(:action_view) do
        require_relative "rails_handler"
        ActionView::Template.register_template_handler(:slim, SuperSlim::RailsHandler.new)
      end
    end
  end
end
