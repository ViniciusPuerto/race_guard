# frozen_string_literal: true

Rails.application.configure do
  config.active_job.queue_adapter = :test
  config.enable_reloading = true
  config.eager_load = false
  config.consider_all_requests_local = true
  config.secret_key_base = 'rmw_rails_example_app_test_secret_key_base_0123456789'
  config.action_controller.perform_caching = false
  config.cache_store = :null_store
  config.active_support.deprecation = :stderr
  config.active_record.migration_error = :page_load
end
