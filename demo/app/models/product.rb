class Product < ApplicationRecord
  has_many :reservations, dependent: :destroy

  validates :sku, presence: true
  validates :name, presence: true
  validates :stock, numericality: { greater_than_or_equal_to: 0 }
end
