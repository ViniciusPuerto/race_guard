require "logger"
require "redis"
require "race_guard/interceptors"

RaceGuard.configure do |c|
  c.environments :development, :test
  c.enable :db_lock_auditor
  c.enable :distributed_guard
  c.distributed_redis_client Redis.new(url: ENV.fetch("REDIS_URL", "redis://localhost:6379/0"))
  c.distributed_skip_behavior :sentinel
  c.distributed_key_prefix "race_guard:demo"

  report_file = Rails.root.join("log", "race_guard_events.jsonl")
  report_io = File.open(report_file, "a")
  report_io.sync = true
  c.add_reporter(RaceGuard::Reporters::JsonReporter.new(report_io))

end

Rails.application.config.after_initialize do
  RaceGuard.configure do |c|
    c.db_lock_read_modify_write_models(Wallet, Product)
  end
  RaceGuard::Interceptors.install_active_job!
  RaceGuard::Interceptors.install_action_mailer!
end
