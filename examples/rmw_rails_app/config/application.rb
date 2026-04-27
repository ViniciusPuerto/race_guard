# frozen_string_literal: true

require_relative 'boot'

require 'rails'
require 'active_model/railtie'
require 'active_record/railtie'
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
  end
end
