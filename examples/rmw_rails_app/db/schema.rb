# frozen_string_literal: true

ActiveRecord::Schema[7.2].define(version: 20_250_427_000_001) do
  create_table 'wallets', force: :cascade do |t|
    t.integer 'balance', default: 0, null: false
  end
end
