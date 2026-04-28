# frozen_string_literal: true

Rails.application.config.after_initialize do
  RaceGuard.configure do |c|
    c.add_reporter RaceGuard::Reporters::LogReporter.new(Rails.logger)
    c.db_lock_read_modify_write_models(Wallet)

    # Optional Epic 10 demo: fleet-wide lock (requires Redis). Uncomment for
    # `race_guard:distributed_cron_demo` or to enforce single-winner Sidekiq bumps per wallet.
    # require "redis"
    # c.enable(:distributed_guard)
    # c.distributed_redis_client(Redis.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0')))
    # c.severity(:distributed_guard, :warn)
  end
end
