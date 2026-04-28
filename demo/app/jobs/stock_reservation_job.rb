class StockReservationJob
  include Sidekiq::Job

  def perform(product_id, user_id, quantity)
    product = Product.find(product_id)
    user = User.find(user_id)
    qty = quantity.to_i

    Product.transaction do
      product.lock!
      return if product.stock < qty

      product.update!(stock: product.stock - qty)
      Reservation.create!(user: user, product: product, quantity: qty, status: "reserved")
    end
  rescue ActiveRecord::RecordNotUnique
    RaceGuard.report(detector: "reservation_uniqueness", message: "duplicate reservation prevented", severity: :info)
  end
end
