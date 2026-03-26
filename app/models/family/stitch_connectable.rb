# Adds Stitch (South African open banking) connectivity to the Family model.
# Stitch is the primary open-banking provider for the SA market.
module Family::StitchConnectable
  extend ActiveSupport::Concern

  included do
    has_many :stitch_items, dependent: :destroy
  end

  # Stitch is available whenever SA market credentials are configured globally
  # or via environment variables (family-level credentials not required).
  def can_connect_stitch?
    stitch_credentials_present? || sa_market?
  end

  def sa_market?
    market_mode == "sa"
  end

  def global_market?
    market_mode == "global"
  end

  private

    def stitch_credentials_present?
      ENV["STITCH_CLIENT_ID"].present? || Rails.application.credentials.dig(:stitch, :client_id).present?
    end
end
