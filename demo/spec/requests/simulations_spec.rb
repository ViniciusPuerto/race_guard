require "rails_helper"

RSpec.describe "Simulations", type: :request do
  let!(:user) { User.create!(email: "spec@example.com", name: "Spec User") }
  let!(:wallet) { Wallet.create!(user: user, balance_cents: 0) }
  let!(:product) { Product.create!(sku: "spec-sku", name: "Spec Product", stock: 20) }

  it "enqueues wallet race scenario" do
    post "/simulations/wallet_race/run", params: { wallet_id: wallet.id, amount_cents: 10, times: 3 }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["scenario"]).to eq("wallet_race")
    expect(json["enqueued"]).to eq(3)
  end

  it "enqueues stock race scenario" do
    post "/simulations/stock_race/run", params: { product_id: product.id, user_id: user.id, quantity: 1, times: 2 }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["scenario"]).to eq("stock_race")
    expect(json["enqueued"]).to eq(2)
  end

  it "enqueues once run scenario" do
    post "/simulations/once_run/run", params: { wallet_id: wallet.id, amount_cents: 10, times: 4, run_key: "spec-key" }

    expect(response).to have_http_status(:ok)
    json = JSON.parse(response.body)
    expect(json["scenario"]).to eq("once_run")
    expect(json["enqueued"]).to eq(4)
  end
end
