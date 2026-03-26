# =============================================================================
# StitchAccount — A single SA bank account linked via Stitch
# =============================================================================
#
# CONCEPT
# -------
# StitchAccount is the join between a Stitch API bankAccount object and an
# OTCapital Account record. It mirrors the same pattern used by
# EnableBankingAccount (EU) and PlaidAccount (US).
#
# Each StitchAccount:
#   • belongs_to a StitchItem (the Stitch consent grant / bank connection)
#   • has_one Account via the account_providers polymorphic table
#   • stores a raw_payload snapshot of the last Stitch API response
#
# DB COLUMNS (see migration 20260326100001_create_stitch_tables)
# --------------------------------------------------------------
#   remote_id             — Stitch bankAccount.id (UUID). Unique across the app.
#   bank_id               — Stitch bank identifier, e.g. "fnb", "absa"
#   bank_name             — Human-readable bank name, e.g. "First National Bank"
#   account_type          — Raw Stitch type: "cheque", "savings", "creditCard", "loan"
#   account_number_masked — Last 4 digits only, e.g. "•••• 1234" (PCI safety)
#   currency              — ISO code, almost always "ZAR"
#   raw_payload           — Full JSON from Stitch for debugging / future fields
#
# ACCOUNT TYPE MAPPING
# --------------------
# Stitch uses SA-specific type names. SA_ACCOUNT_TYPE_MAP translates them to
# OTCapital's internal accountable_type strings so the existing account
# rendering logic (charts, reports) works without modification.
#
# HOW ACCOUNT LINKING WORKS
# --------------------------
# The account_providers table (polymorphic) is the bridge:
#   account_providers.provider_type = "StitchAccount"
#   account_providers.provider_id   = stitch_account.id
#   account_providers.account_id    = account.id
#
# This means one Account can only have one StitchAccount linked to it at a
# time (enforced by the account_providers uniqueness constraint). If a user
# re-links the same bank, find_or_initialize_by(remote_id:) ensures we reuse
# the existing StitchAccount row rather than creating a duplicate.
#
class StitchAccount < ApplicationRecord
  include CurrencyNormalizable

  belongs_to :stitch_item
  has_one :family, through: :stitch_item

  # Polymorphic join → Account (same pattern as EnableBankingAccount)
  # Developer note: never set account_id directly — go through account_provider.
  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, through: :account_provider, source: :account

  validates :remote_id, presence: true, uniqueness: true
  validates :currency,  presence: true

  # Maps Stitch's SA-specific account type strings to OTCapital's accountable_type.
  # Update this map if Stitch introduces new account types (check their API changelog).
  SA_ACCOUNT_TYPE_MAP = {
    "cheque"     => "Depository",   # Standard SA cheque account
    "savings"    => "Depository",   # Savings account (same OT type as cheque)
    "creditCard" => "CreditCard",   # Credit card
    "loan"       => "Loan"          # Personal or home loan
  }.freeze

  # Returns a human-readable account type for display in the UI.
  def account_type_display
    SA_ACCOUNT_TYPE_MAP[account_type] || account_type&.titleize || "Bank Account"
  end

  # Persist a fresh snapshot from the Stitch GraphQL bankAccount payload.
  # Called both during initial account setup and on every sync.
  # raw_payload stores the full response for debugging and future field expansion.
  def upsert_stitch_snapshot!(payload)
    update!(
      bank_id:               payload["bankId"],
      bank_name:             payload["bankName"],
      account_type:          payload["accountType"],
      account_number_masked: masked_account_number(payload["accountNumber"]),
      currency:              parse_currency(payload["currency"]) || "ZAR",
      raw_payload:           payload
    )
  end

  private

    # Store only last 4 digits — never store a full account number.
    def masked_account_number(number)
      return nil if number.blank?

      "•••• #{number.last(4)}"
    end

    # Required by CurrencyNormalizable — called when parse_currency returns nil.
    def log_invalid_currency(currency_value)
      Rails.logger.warn("Invalid currency '#{currency_value}' for StitchAccount #{id}, defaulting to ZAR")
    end
end
