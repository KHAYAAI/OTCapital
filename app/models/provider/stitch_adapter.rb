# =============================================================================
# Provider::StitchAdapter — Plugs Stitch into OTCapital's provider framework
# =============================================================================
#
# ROLE IN THE ARCHITECTURE
# -------------------------
# Provider::Factory is a registry that maps provider account class names to
# their adapter classes. When the sync infrastructure encounters a StitchAccount
# it calls Provider::Factory.for("StitchAccount") which returns this adapter.
#
# This adapter bridges StitchAccount (our AR model) and Provider::Stitch (the
# raw API client) by implementing the interface defined in Provider::Base.
#
# MODULES INCLUDED
# ----------------
# Provider::Syncable      — adds sync_account, sync_holdings, etc. used by SyncJob
# Provider::InstitutionMetadata — common bank metadata methods (name, color, url)
#
# TO ADD A NEW PROVIDER
# ----------------------
# Follow this exact pattern:
#   1. Create app/models/provider/<name>.rb           (API client)
#   2. Create app/models/provider/<name>_adapter.rb   (this file's equivalent)
#   3. Create app/models/<name>_item.rb               (consent/connection record)
#   4. Create app/models/<name>_account.rb            (individual account record)
#   5. Create app/models/family/<name>_connectable.rb (Family concern)
#   6. Create migration for the two tables
#   7. Add routes in config/routes.rb
#   8. Create controller
#
class Provider::StitchAdapter < Provider::Base
  include Provider::Syncable
  include Provider::InstitutionMetadata

  # Register with the factory so syncs on StitchAccount records route here.
  Provider::Factory.register("StitchAccount", self)

  # Which OTCapital accountable types this provider can supply.
  # Used by the "Connect account" UI to filter compatible account types.
  def self.supported_account_types
    %w[Depository CreditCard Loan]
  end

  # Returns the connection config hash shown in Settings → Providers.
  # Returns [] if the family cannot connect to Stitch (no creds + wrong market).
  # The `new_account_path` and `existing_account_path` lambdas are called by
  # the shared account connection UI to build the correct link URL.
  def self.connection_configs(family:)
    return [] unless family.can_connect_stitch?

    [
      {
        key:          "stitch",
        name:         "Stitch (South Africa)",
        description:  "Connect your South African bank account via Stitch Money",
        can_connect:  true,
        new_account_path: ->(accountable_type, _return_to) {
          Rails.application.routes.url_helpers.new_stitch_item_path(
            accountable_type: accountable_type
          )
        },
        existing_account_path: ->(account_id) {
          Rails.application.routes.url_helpers.select_existing_account_stitch_items_path(
            account_id: account_id
          )
        }
      }
    ]
  end

  def provider_name
    "stitch"
  end

  def sync_path
    Rails.application.routes.url_helpers.sync_stitch_item_path(item)
  end

  def item
    provider_account.stitch_item
  end

  def can_delete_holdings?
    false
  end

  def institution_domain
    nil
  end

  def institution_name
    provider_account.bank_name.presence || item&.name
  end

  def institution_url
    nil
  end

  def institution_color
    nil
  end
end
