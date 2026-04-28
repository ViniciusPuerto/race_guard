namespace :demo do
  desc "Enqueue wallet race jobs"
  task wallet_race: :environment do
    wallet = Wallet.first || Wallet.create!(user: User.first || User.create!(name: "Demo", email: "demo@example.com"))
    20.times { ConcurrentChargeJob.perform_async(wallet.id, 100) }
    puts "Enqueued 20 ConcurrentChargeJob jobs for wallet ##{wallet.id}"
  end

  desc "Enqueue stock reservation jobs"
  task stock_race: :environment do
    user = User.first || User.create!(name: "Demo", email: "demo@example.com")
    product = Product.first || Product.create!(sku: "sku-1", name: "Demo Product", stock: 10)
    20.times { StockReservationJob.perform_async(product.id, user.id, 1) }
    puts "Enqueued 20 StockReservationJob jobs for product ##{product.id}"
  end

  desc "Enqueue once-only settlement jobs"
  task once_run: :environment do
    user = User.first || User.create!(name: "Demo", email: "demo@example.com")
    wallet = user.wallet || Wallet.create!(user: user, balance_cents: 0)
    run_key = Time.now.utc.strftime("%Y%m%d%H%M")
    20.times { OnceOnlySettlementJob.perform_async(run_key, wallet.id, 50) }
    puts "Enqueued 20 OnceOnlySettlementJob jobs for run_key=#{run_key}"
  end
end
