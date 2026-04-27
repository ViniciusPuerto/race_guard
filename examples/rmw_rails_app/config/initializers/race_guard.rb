# frozen_string_literal: true

Rails.application.config.after_initialize do
  RaceGuard.configure do |c|
    c.add_reporter RaceGuard::Reporters::LogReporter.new(Rails.logger)
    c.db_lock_read_modify_write_models(Wallet)
  end
end
