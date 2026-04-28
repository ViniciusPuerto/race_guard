user = User.find_or_create_by!(email: "alice@example.com") { |u| u.name = "Alice" }
wallet = Wallet.find_or_create_by!(user: user) { |w| w.balance_cents = 10_000 }
product = Product.find_or_create_by!(sku: "book-001") { |p| p.name = "Concurrency Book"; p.stock = 25 }

puts "Seeded user=#{user.id}, wallet=#{wallet.id}, product=#{product.id}"
# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
#   ["Action", "Comedy", "Drama", "Horror"].each do |genre_name|
#     MovieGenre.find_or_create_by!(name: genre_name)
#   end
