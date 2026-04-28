class BillingRun < ApplicationRecord
  validates :run_key, presence: true
  validates :status, presence: true
end
