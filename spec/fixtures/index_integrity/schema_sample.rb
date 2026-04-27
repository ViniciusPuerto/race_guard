# frozen_string_literal: true

# Fixture: Rails 7-style schema fragment for SchemaAnalyzer specs.
ActiveRecord::Schema[7.1].define(version: 20_240_101_000_000) do
  create_table 'users', force: :cascade do |t|
    t.string 'email'
    t.index ['email'], name: 'index_users_on_email', unique: true
  end

  create_table 'accounts', force: :cascade do |t|
    t.string 'slug'
    t.string 'tenant_id'
  end

  add_index 'accounts', %w[slug tenant_id], unique: true,
                                            name: 'index_accounts_on_slug_and_tenant_id'
  add_index 'accounts', ['slug'], unique: false, name: 'index_accounts_on_slug_nonunique'
end
