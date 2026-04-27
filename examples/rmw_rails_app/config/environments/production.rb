# frozen_string_literal: true

Rails.application.configure do
  config.enable_reloading = false
  config.eager_load = true
  config.consider_all_requests_local = false
  config.secret_key_base = ENV.fetch('SECRET_KEY_BASE', 'rmw_rails_example_app_production_secret_key_base_0123456789')
  config.action_controller.perform_caching = true
  config.public_file_server.enabled = ENV['RAILS_SERVE_STATIC_FILES'].present?
  config.active_record.dump_schema_after_migration = false
  config.active_support.report_deprecations = false
  config.assets.compile = false
end
