class JobsController < ApplicationController
  def once_charge_run
    run_key = params.fetch(:run_key, Time.now.utc.strftime("%Y%m%d%H%M"))
    wallet_id = Integer(params.fetch(:wallet_id))
    amount = Integer(params.fetch(:amount_cents, 100))

    5.times { OnceOnlySettlementJob.perform_async(run_key, wallet_id, amount) }

    render json: { enqueued: 5, run_key: run_key, wallet_id: wallet_id, amount_cents: amount }
  end
end
