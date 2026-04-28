class OnceOnlySettlementJob
  include Sidekiq::Job

  def perform(run_key, wallet_id, amount_cents)
    RaceGuard.distributed_once("once_only_settlement", ttl: 30, resource: run_key, on_skip: :sentinel) do |lock|
      BillingRun.create_or_find_by!(run_key: run_key) do |run|
        run.status = "started"
        run.metadata = { wallet_id: wallet_id, amount_cents: amount_cents.to_i }
      end

      wallet = Wallet.find(wallet_id)
      wallet.with_lock do
        wallet.update!(balance_cents: wallet.balance_cents + amount_cents.to_i)
      end
      lock.renew(ttl: 30)
      BillingRun.find_by!(run_key: run_key).update!(status: "finished")
    end
  rescue RaceGuard::Distributed::LockNotAcquiredError
    RaceGuard.report(detector: "once_only_settlement", message: "lock not acquired", severity: :info, context: { run_key: run_key })
  end
end
