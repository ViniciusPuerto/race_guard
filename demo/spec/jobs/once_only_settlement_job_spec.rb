require "rails_helper"

RSpec.describe OnceOnlySettlementJob do
  it "invokes race_guard distributed_once wrapper" do
    user = User.create!(email: "job@example.com", name: "Job User")
    wallet = Wallet.create!(user: user, balance_cents: 0)
    lock_control = instance_double("LockControl", renew: true)

    allow(RaceGuard).to receive(:distributed_once).and_yield(lock_control)

    described_class.new.perform("run-1", wallet.id, 25)

    expect(RaceGuard).to have_received(:distributed_once).with(
      "once_only_settlement",
      ttl: 30,
      resource: "run-1",
      on_skip: :sentinel
    )
    expect(wallet.reload.balance_cents).to eq(25)
  end
end
