# frozen_string_literal: true

# Intentional read–modify–write: concurrent jobs each reload, read +balance+, then +update!+.
# race_guard's DB RMW detector is per-thread; this demo shows concurrent updates + Sidekiq wiring,
# not necessarily one detector line per job.
class WalletBumpJob
  include Sidekiq::Job

  def perform(wallet_id)
    RaceGuard.distributed_once(
      'wallet_bump_job',
      resource: wallet_id.to_s,
      ttl: 60
    ) do
      w = Wallet.find(wallet_id)
      w.reload
      current = w.balance
      w.update!(balance: current + 1)
    end
  end
end
