# frozen_string_literal: true

namespace :race_guard do
  desc 'Intentional read–modify–write on Wallet; logs db_lock_auditor:read_modify_write'
  task demo: :environment do
    w = Wallet.first!
    _read = w.balance
    w.update!(balance: w.balance - 1)
    puts 'Done. Check log lines for detector db_lock_auditor:read_modify_write.'
  end
end
