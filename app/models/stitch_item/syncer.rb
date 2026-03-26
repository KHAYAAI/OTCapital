# =============================================================================
# StitchItem::Syncer — Pulls fresh data from Stitch and persists it
# =============================================================================
#
# CALLED BY
# ---------
# StitchItem::Provided#syncer returns an instance of this class.
# Syncable (the concern included in StitchItem) calls syncer.sync_data when
# a background sync job runs (triggered by StitchItem#sync_later).
#
# WHAT IT DOES PER SYNC
# ----------------------
# 1. Re-exchanges the stored user_interaction_id for a fresh access token.
# 2. Fetches all bank accounts for this Stitch connection.
# 3. For each account that has been linked to an OTCapital Account:
#    a. Updates the snapshot in stitch_accounts (balance, bank name, type)
#    b. Updates the account.balance with the latest currentBalance from Stitch
#    c. Fetches transactions since start_date and writes new Entry records
#
# IDEMPOTENCY
# -----------
# build_entry_from_stitch_transaction checks for an existing entry by
# data->>'stitch_id' before creating. Re-running a sync is safe — no
# duplicates will be created.
#
# TRANSACTION SIGN CONVENTION
# ---------------------------
# OTCapital stores amounts as positive = money OUT (expense), negative = money IN.
# Stitch uses "direction": "debit"  → money leaving  → positive in OTCapital
#             "direction": "credit" → money arriving → negative in OTCapital
#
# TOKEN MANAGEMENT NOTE
# ---------------------
# Currently we re-exchange user_interaction_id on every sync. This works while
# Stitch allows it, but you should implement a token refresh/storage strategy
# once you move to production. Store the user_access_token in stitch_items
# and only re-exchange when it has expired (check token_expires_at).
#
# TODO for the team
# -----------------
# [ ] Store user_token in stitch_items after exchange so we don't re-exchange
#     on every sync (reduces Stitch API calls and avoids single-use code issues)
# [ ] Implement Stitch webhook support for real-time transaction pushes
#     See: https://stitch.money/docs/webhooks
# [ ] Add retry/backoff when Stitch returns transient errors (:api_error reason)
#
class StitchItem::Syncer
  attr_reader :stitch_item

  def initialize(stitch_item)
    @stitch_item = stitch_item
  end

  # Entry point — called by the Syncable background job infrastructure.
  # start_date is passed by the sync job when re-syncing a specific date range.
  def sync_data(start_date: nil)
    stitch = stitch_item.stitch_provider
    user_token = exchange_token(stitch)

    remote_accounts = stitch.get_accounts(user_token: user_token)
    sync_accounts(stitch, user_token, remote_accounts, start_date: start_date)
  end

  private

    # Exchange the stored user_interaction_id for a live access token.
    # The redirect_uri must match exactly what was used when creating the link token.
    def exchange_token(stitch)
      result = stitch.exchange_user_token(
        user_interaction_id: stitch_item.user_interaction_id,
        redirect_uri: callback_url
      )
      result["access_token"]
    end

    # The callback URL must match the redirect_uri registered in the Stitch dashboard.
    # In production, set action_mailer.default_url_options[:host] to your domain.
    def callback_url
      Rails.application.routes.url_helpers.callback_stitch_items_url(
        host: Rails.application.config.action_mailer.default_url_options&.dig(:host) || "localhost"
      )
    end

    # Iterate over every Stitch bankAccount, find the matching local StitchAccount,
    # refresh its snapshot, update the balance, and pull new transactions.
    # Accounts not yet linked (stitch_acct.account is nil) are skipped silently.
    def sync_accounts(stitch, user_token, remote_accounts, start_date:)
      remote_accounts.each do |remote_acct|
        stitch_acct = stitch_item.stitch_accounts.find_by(remote_id: remote_acct["id"])
        next unless stitch_acct&.account  # skip unlinked accounts

        stitch_acct.upsert_stitch_snapshot!(remote_acct)

        # Update the OTCapital account balance with Stitch's latest figure
        balance = remote_acct["currentBalance"].to_d
        stitch_acct.account.update!(balance: balance) if balance.present?

        sync_transactions(stitch, user_token, stitch_acct, start_date: start_date)
      end
    end

    def sync_transactions(stitch, user_token, stitch_acct, start_date:)
      transactions = stitch.get_transactions(
        user_token: user_token,
        account_id: stitch_acct.remote_id,
        from_date:  start_date
      )

      transactions.each do |txn|
        build_entry_from_stitch_transaction(stitch_acct.account, txn)
      end
    end

    # Create an Entry + Transaction for a Stitch transaction payload.
    # Skips transactions that already exist (deduped by stitch_id in data JSONB).
    def build_entry_from_stitch_transaction(account, txn)
      return unless txn["id"].present?

      # Idempotency check — data is a JSONB column on entries
      existing = account.entries.find_by("data->>'stitch_id' = ?", txn["id"])
      return if existing.present?

      amount = BigDecimal(txn["amount"].to_s)
      # Stitch sign convention: "debit" = money leaving the account (positive expense)
      signed_amount = txn["direction"] == "debit" ? amount : -amount

      account.entries.create!(
        date:     Date.parse(txn["date"]),
        amount:   signed_amount,
        currency: txn["currency"].presence || "ZAR",
        name:     txn["description"].presence || "Stitch Transaction",
        entryable: Transaction.new(
          date:     Date.parse(txn["date"]),
          amount:   signed_amount,
          currency: txn["currency"].presence || "ZAR",
          name:     txn["description"].presence || "Stitch Transaction"
        ),
        # Store Stitch IDs in the data JSONB for deduplication and traceability
        data: { stitch_id: txn["id"], stitch_reference: txn["reference"] }
      )
    rescue => e
      # Log and continue — one bad transaction should not abort the entire sync
      Rails.logger.warn("StitchItem::Syncer: failed to create entry for txn #{txn['id']}: #{e.message}")
    end
end
