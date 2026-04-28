class WalletsController < ApplicationController
  def charge_naive
    wallet = Wallet.find(params[:id])
    amount = Integer(params.fetch(:amount_cents, 100))

    RaceGuard.protect("wallet:charge_naive") do
      current = wallet.balance_cents
      sleep 0.05
      wallet.update!(balance_cents: current + amount)
    end

    ConcurrentChargeJob.perform_async(wallet.id, amount)

    render json: { scenario: "naive", wallet_id: wallet.id, balance_cents: wallet.reload.balance_cents }
  end

  def charge_safe
    wallet = Wallet.find(params[:id])
    amount = Integer(params.fetch(:amount_cents, 100))

    Wallet.transaction do
      wallet.with_lock do
        wallet.update!(balance_cents: wallet.balance_cents + amount)
      end
      RaceGuard.after_commit { ConcurrentChargeJob.perform_async(wallet.id, amount) }
    end

    render json: { scenario: "safe", wallet_id: wallet.id, balance_cents: wallet.reload.balance_cents }
  end
end
