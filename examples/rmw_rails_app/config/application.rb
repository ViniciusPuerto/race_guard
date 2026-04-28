# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
require 'active_job/railtie'
require 'action_controller/railtie'
require 'action_view/railtie'
require 'sprockets/railtie'

Bundler.require(*Rails.groups)

module RmwRailsApp
  class Application < Rails::Application
    config.load_defaults 7.2
    config.api_only = false
    config.eager_load = false
    config.generators.system_tests = nil

    # Register as its own Zeitwerk root so files here are top-level constants (not Sidekiq::...).
    config.autoload_paths << root.join('app', 'sidekiq')
    config.eager_load_paths << root.join('app', 'sidekiq')
  end
end
