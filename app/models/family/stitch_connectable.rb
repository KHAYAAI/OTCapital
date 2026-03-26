# =============================================================================
# Family::StitchConnectable — Adds Stitch SA open-banking to Family
# =============================================================================
#
# PATTERN
# -------
# Follows the same pattern as Family::PlaidConnectable, ::EnableBankingConnectable
# etc. Each provider gets its own concern so Family stays skinny and each
# provider's logic is self-contained and easy to find.
#
# This concern is included at the top of app/models/family.rb:
#   include StitchConnectable
#
# MARKET MODE vs CREDENTIALS
# --------------------------
# can_connect_stitch? returns true under TWO conditions (either is enough):
#
#   1. Stitch credentials are present in ENV or Rails credentials file.
#      → Allows Stitch even if the family is in "global" mode (e.g. an SA
#        user who chose global mode but still wants to link their SA bank).
#
#   2. The family is in SA market mode (market_mode == "sa").
#      → Shows the Stitch option by default for all SA users, even before
#        credentials are configured (the panel will display a warning instead
#        of hiding the option entirely).
#
# HOW TO CHECK MARKET MODE IN VIEWS / CONTROLLERS
# -------------------------------------------------
#   Current.family.sa_market?     # → true when market_mode == "sa"
#   Current.family.global_market? # → true when market_mode == "global"
#
# These two helpers cover all cases — market_mode is validated to only be
# "sa" or "global" (see Family::MARKET_MODES and the validation).
#
module Family::StitchConnectable
  extend ActiveSupport::Concern

  included do
    # A family can have many Stitch connections (one per bank / consent grant)
    has_many :stitch_items, dependent: :destroy
  end

  # Gates the Stitch option in the providers UI and controller flows.
  # Returns true if credentials exist OR if this is an SA-market family.
  def can_connect_stitch?
    stitch_credentials_present? || sa_market?
  end

  # True when this family has chosen South Africa as their primary market.
  # Use in views:  <% if Current.family.sa_market? %>
  def sa_market?
    market_mode == "sa"
  end

  # True when this family has chosen the global (US/EU) market mode.
  def global_market?
    market_mode == "global"
  end

  private

    # Checks both ENV and Rails credentials for Stitch keys.
    # ENV takes precedence (better for Docker/Heroku deployments).
    def stitch_credentials_present?
      ENV["STITCH_CLIENT_ID"].present? || Rails.application.credentials.dig(:stitch, :client_id).present?
    end
end
