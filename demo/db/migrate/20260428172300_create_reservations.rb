class CreateReservations < ActiveRecord::Migration[7.2]
  def change
    create_table :reservations do |t|
      t.references :user, null: false, foreign_key: true
      t.references :product, null: false, foreign_key: true
      t.integer :quantity, null: false, default: 1
      t.string :status, null: false, default: "pending"

      t.timestamps
    end

    add_index :reservations, [:user_id, :product_id, :status], unique: true, name: "idx_unique_active_reservation"
  end
end
