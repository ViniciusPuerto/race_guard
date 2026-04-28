# frozen_string_literal: true

namespace :race_guard do
  desc 'Intentional read–modify–write on Wallet; logs db_lock_auditor:read_modify_write'
  task demo: :environment do
    w = Wallet.first!
    _read = w.balance
    w.update!(balance: w.balance - 1)
    puts 'Done. Check log lines for detector db_lock_auditor:read_modify_write.'
  end

  desc 'Simulate duplicate cron hosts: only one winner runs the body per TTL when distributed_guard is enabled'
  task distributed_cron_demo: :environment do
    result = RaceGuard.distributed_once('cron:race_guard_demo_export', ttl: 120) do
      Rails.logger.info('[race_guard] distributed_cron_demo: body ran')
      :ran_body
    end
    puts "distributed_once returned #{result.inspect} (nil means skipped — enable :distributed_guard + Redis in initializer)"
  end

  desc 'Enqueue many WalletBumpJob jobs for the same wallet (needs Redis + Sidekiq running)'
  task sidekiq_demo: :environment do
    w = Wallet.first!
    w.update!(balance: 0)
    n = ENV.fetch('RACE_GUARD_SIDEKIQ_JOBS', '50').to_i
    n.times { WalletBumpJob.perform_async(w.id) }
    puts <<~MSG
      Enqueued #{n} WalletBumpJob jobs for wallet id=#{w.id} (balance reset to 0).

      In another terminal (from this directory, Redis running):
        RAILS_ENV=development bundle exec sidekiq

      After jobs finish, expect balance < #{n} if updates raced (lost increments).
      Check log/development.log for race_guard / db_lock_auditor lines as applicable.
    MSG
  end
end
