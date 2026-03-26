# Creates the two tables required for the Stitch SA open-banking integration.
#
# TABLES
# ------
# stitch_items     — One row per bank consent grant (one per bank per family)
# stitch_accounts  — One row per bank account within a consent grant
#
# AFTER DEPLOY
# ------------
# Run:  bin/rails db:migrate
#
# RELATIONSHIP DIAGRAM
# --------------------
# families (1) ──< stitch_items (1) ──< stitch_accounts (1) ──> accounts
#
# The accounts link goes via the polymorphic account_providers table
# (not a direct FK here) — see StitchAccount for the has_one :account_provider.
#
class CreateStitchTables < ActiveRecord::Migration[7.2]
  def change
    # -------------------------------------------------------------------------
    # stitch_items — one record per Stitch consent grant
    # -------------------------------------------------------------------------
    create_table :stitch_items, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :family, null: false, foreign_key: true, type: :uuid

      t.string :name, null: false              # user-visible label, e.g. "My FNB"

      # OAuth fields — populated during the consent flow
      t.string :token_id                       # Stitch link token ID (step 2 of OAuth)
      t.string :user_interaction_id            # Code from Stitch callback (step 3 of OAuth).
                                               # Exchange this for a user token via
                                               # Provider::Stitch#exchange_user_token.
                                               # Treat as sensitive — single-use credential.
      t.string   :status, default: "good", null: false  # "good" | "requires_update"
      t.boolean  :scheduled_for_deletion, default: false, null: false  # soft-delete flag
      t.datetime :token_expires_at             # optional: when the Stitch user token expires
      t.jsonb    :raw_payload, default: {}     # latest raw API response for debugging

      t.timestamps
    end

    # -------------------------------------------------------------------------
    # stitch_accounts — one record per bank account within a consent grant
    # -------------------------------------------------------------------------
    create_table :stitch_accounts, id: :uuid, default: -> { "gen_random_uuid()" } do |t|
      t.references :stitch_item, null: false, foreign_key: true, type: :uuid
      t.references :account,     null: false, foreign_key: true, type: :uuid  # OTCapital Account

      t.string :remote_id, null: false         # Stitch bankAccount.id (UUID from Stitch)
      t.string :bank_id                        # e.g. "fnb", "absa", "capitec"
      t.string :bank_name                      # e.g. "First National Bank"
      t.string :account_type                   # Stitch type: "cheque", "savings", "creditCard", "loan"
      t.string :account_number_masked          # e.g. "•••• 1234" — last 4 digits only
      t.string :currency, default: "ZAR"       # ISO code; almost always ZAR
      t.jsonb  :raw_payload, default: {}       # full Stitch bankAccount payload

      t.timestamps
    end

    # Enforce uniqueness on the Stitch remote ID — prevents duplicate accounts
    # if a sync runs twice or a user re-links the same bank account.
    add_index :stitch_accounts, :remote_id, unique: true
  end
end
