class SimulationsController < ApplicationController
  def run
    scenario = params.fetch(:scenario)
    case scenario
    when "wallet_race"
      invoke_wallet_race
    when "stock_race"
      invoke_stock_race
    when "once_run"
      invoke_once_run
    else
      render json: { error: "unknown scenario" }, status: :unprocessable_entity
    end
  end

  private

  def invoke_wallet_race
    wallet = Wallet.find(Integer(params.fetch(:wallet_id)))
    amount = Integer(params.fetch(:amount_cents, 100))
    times = Integer(params.fetch(:times, 10))

    times.times { ConcurrentChargeJob.perform_async(wallet.id, amount) }
    render json: { scenario: "wallet_race", enqueued: times, wallet_id: wallet.id, amount_cents: amount }
  end

  def invoke_stock_race
    product = Product.find(Integer(params.fetch(:product_id)))
    user = User.find(Integer(params.fetch(:user_id)))
    quantity = Integer(params.fetch(:quantity, 1))
    times = Integer(params.fetch(:times, 10))

    times.times { StockReservationJob.perform_async(product.id, user.id, quantity) }
    render json: { scenario: "stock_race", enqueued: times, product_id: product.id, user_id: user.id, quantity: quantity }
  end

  def invoke_once_run
    run_key = params.fetch(:run_key, Time.now.utc.strftime("%Y%m%d%H%M"))
    wallet = Wallet.find(Integer(params.fetch(:wallet_id)))
    amount = Integer(params.fetch(:amount_cents, 100))
    times = Integer(params.fetch(:times, 10))

    times.times { OnceOnlySettlementJob.perform_async(run_key, wallet.id, amount) }
    render json: { scenario: "once_run", enqueued: times, run_key: run_key, wallet_id: wallet.id, amount_cents: amount }
  end
end
