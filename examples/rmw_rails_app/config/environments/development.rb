# frozen_string_literal: true

require 'active_support/core_ext/integer/time'

Rails.application.configure do
  config.active_job.queue_adapter = :sidekiq
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base = 'rmw_rails_example_app_development_secret_key_base_0123456789'
  config.server_timing = true
  config.action_controller.perform_caching = false
  config.cache_store = :null_store
  config.active_support.deprecation = :log
  config.active_record.migration_error = :page_load
  config.active_record.verbose_query_logs = true
  config.assets.debug = true
  config.assets.quiet = true
end
