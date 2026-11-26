# frozen_string_literal: true

module SuperSlim
  class Railtie < Rails::Railtie
    initializer "super_slim.register_template_handler" do
      ActiveSupport.on_load(:action_view) do
        require_relative "rails_handler"
        require "action_view/dependency_tracker" # Rails 8.0 does not autoload it
        ActionView::Template.register_template_handler(:slim, SuperSlim::RailsHandler.new)
        # After the handler: register_tracker looks it up by extension, an unknown one falls back to the Raw handler.
        # Not ERBTracker: since Rails 8.1 it only reads <% %> tags, and finds no render call in Slim.
        ActionView::DependencyTracker.register_tracker(:slim, ActionView::DependencyTracker::RubyTracker)
      end
    end
  end
end
