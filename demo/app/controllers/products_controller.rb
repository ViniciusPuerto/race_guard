class ProductsController < ApplicationController
  def reserve
    product = Product.find(params[:id])
    user = User.find(params.fetch(:user_id))
    quantity = Integer(params.fetch(:quantity, 1))

    reservation = nil
    Product.transaction do
      product.lock!
      raise ActiveRecord::RecordInvalid, product if product.stock < quantity

      product.update!(stock: product.stock - quantity)
      reservation = Reservation.create!(user: user, product: product, quantity: quantity, status: "reserved")
    end

    StockReservationJob.perform_async(product.id, user.id, quantity)

    render json: {
      reservation_id: reservation.id,
      product_id: product.id,
      remaining_stock: product.reload.stock
    }
  end
end
