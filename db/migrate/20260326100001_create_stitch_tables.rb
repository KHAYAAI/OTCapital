class CreateStitchTables < ActiveRecord::Migration[7.2]
  def change
    create_table :stitch_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid
      t.string :name, null: false
      t.string :token_id                    # Stitch link token ID
      t.string :user_interaction_id         # Stitch user interaction reference
      t.string :status, default: "good", null: false
      t.boolean :scheduled_for_deletion, default: false, null: false
      t.datetime :token_expires_at
      t.jsonb :raw_payload, default: {}
      t.timestamps
    end

    create_table :stitch_accounts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :stitch_item, null: false, foreign_key: true, type: :uuid
      t.references :account, null: false, foreign_key: true, type: :uuid
      t.string :remote_id, null: false      # Stitch bankAccount.id
      t.string :bank_id                     # e.g. "fnb", "absa"
      t.string :bank_name
      t.string :account_type               # cheque, savings, creditCard
      t.string :account_number_masked
      t.string :currency, default: "ZAR"
      t.jsonb :raw_payload, default: {}
      t.timestamps
    end

    add_index :stitch_accounts, :remote_id, unique: true
  end
end
