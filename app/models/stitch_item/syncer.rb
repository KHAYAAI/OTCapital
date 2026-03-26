# Handles syncing of account balances and transactions from Stitch for a given StitchItem.
class StitchItem::Syncer
  attr_reader :stitch_item

  def initialize(stitch_item)
    @stitch_item = stitch_item
  end

  def sync_data(start_date: nil)
    stitch = stitch_item.stitch_provider
    user_token = exchange_token(stitch)

    remote_accounts = stitch.get_accounts(user_token: user_token)
    sync_accounts(stitch, user_token, remote_accounts, start_date: start_date)
  end

  private

    def exchange_token(stitch)
      result = stitch.exchange_user_token(
        user_interaction_id: stitch_item.user_interaction_id,
        redirect_uri: callback_url
      )
      result["access_token"]
    end

    def callback_url
      Rails.application.routes.url_helpers.callback_stitch_items_url(
        host: Rails.application.config.action_mailer.default_url_options&.dig(:host) || "localhost"
      )
    end

    def sync_accounts(stitch, user_token, remote_accounts, start_date:)
      remote_accounts.each do |remote_acct|
        stitch_acct = stitch_item.stitch_accounts.find_by(remote_id: remote_acct["id"])
        next unless stitch_acct&.account

        stitch_acct.upsert_stitch_snapshot!(remote_acct)

        # Update account balance
        balance = remote_acct["currentBalance"].to_d
        stitch_acct.account.update!(balance: balance) if balance.present?

        # Sync transactions
        sync_transactions(stitch, user_token, stitch_acct, start_date: start_date)
      end
    end

    def sync_transactions(stitch, user_token, stitch_acct, start_date:)
      transactions = stitch.get_transactions(
        user_token: user_token,
        account_id: stitch_acct.remote_id,
        from_date: start_date
      )

      transactions.each do |txn|
        build_entry_from_stitch_transaction(stitch_acct.account, txn)
      end
    end

    def build_entry_from_stitch_transaction(account, txn)
      return unless txn["id"].present?

      existing = account.entries.find_by("data->>'stitch_id' = ?", txn["id"])
      return if existing.present?

      amount = BigDecimal(txn["amount"].to_s)
      # Stitch uses "debit" = money leaving the account
      signed_amount = txn["direction"] == "debit" ? amount : -amount

      account.entries.create!(
        date: Date.parse(txn["date"]),
        amount: signed_amount,
        currency: txn["currency"].presence || "ZAR",
        name: txn["description"].presence || "Stitch Transaction",
        entryable: Transaction.new(
          date: Date.parse(txn["date"]),
          amount: signed_amount,
          currency: txn["currency"].presence || "ZAR",
          name: txn["description"].presence || "Stitch Transaction"
        ),
        data: { stitch_id: txn["id"], stitch_reference: txn["reference"] }
      )
    rescue => e
      Rails.logger.warn("StitchItem::Syncer: failed to create entry for txn #{txn['id']}: #{e.message}")
    end
end
