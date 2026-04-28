class ConcurrentChargeJob
  include Sidekiq::Job

  def perform(wallet_id, amount_cents)
    wallet = Wallet.find(wallet_id)
    RaceGuard.protect("job:concurrent_charge") do
      current = wallet.balance_cents
      sleep 0.02
      wallet.update!(balance_cents: current + amount_cents.to_i)
    end
  end
end
