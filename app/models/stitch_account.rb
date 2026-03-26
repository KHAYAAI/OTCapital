# Represents a single South African bank account retrieved via the Stitch API.
# Each StitchAccount is linked to one OTCapital Account record.
class StitchAccount < ApplicationRecord
  include CurrencyNormalizable

  belongs_to :stitch_item
  has_one :family, through: :stitch_item

  # Association through account_providers (same pattern as EnableBankingAccount)
  has_one :account_provider, as: :provider, dependent: :destroy
  has_one :account, through: :account_provider, source: :account

  validates :remote_id, presence: true, uniqueness: true
  validates :currency,  presence: true

  SA_ACCOUNT_TYPE_MAP = {
    "cheque"     => "Depository",
    "savings"    => "Depository",
    "creditCard" => "CreditCard",
    "loan"       => "Loan"
  }.freeze

  def account_type_display
    SA_ACCOUNT_TYPE_MAP[account_type] || account_type&.titleize || "Bank Account"
  end

  # Upsert account data from a Stitch GraphQL bankAccount payload
  def upsert_stitch_snapshot!(payload)
    update!(
      bank_id:              payload["bankId"],
      bank_name:            payload["bankName"],
      account_type:         payload["accountType"],
      account_number_masked: masked_account_number(payload["accountNumber"]),
      currency:             parse_currency(payload["currency"]) || "ZAR",
      raw_payload:          payload
    )
  end

  private

    def masked_account_number(number)
      return nil if number.blank?

      "•••• #{number.last(4)}"
    end

    def log_invalid_currency(currency_value)
      Rails.logger.warn("Invalid currency '#{currency_value}' for StitchAccount #{id}, defaulting to ZAR")
    end
end
