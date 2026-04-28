class CreateBillingRuns < ActiveRecord::Migration[7.2]
  def change
    create_table :billing_runs do |t|
      t.string :run_key, null: false
      t.string :status, null: false, default: "started"
      t.jsonb :metadata, null: false, default: {}

      t.timestamps
    end

    add_index :billing_runs, :run_key, unique: true
  end
end
