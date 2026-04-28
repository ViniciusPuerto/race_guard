class CreateWallets < ActiveRecord::Migration[7.2]
  def change
    create_table :wallets do |t|
      t.references :user, null: false, foreign_key: true, index: false
      t.integer :balance_cents, null: false, default: 0

      t.timestamps
    end

    add_index :wallets, :user_id, unique: true
  end
end
