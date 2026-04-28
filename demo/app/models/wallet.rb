class Wallet < ApplicationRecord
  belongs_to :user

  validates :balance_cents, numericality: { greater_than_or_equal_to: 0 }
end
