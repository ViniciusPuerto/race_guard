class User < ApplicationRecord
  has_one :wallet, dependent: :destroy
  has_many :reservations, dependent: :destroy

  validates :email, presence: true
  validates :name, presence: true
end
