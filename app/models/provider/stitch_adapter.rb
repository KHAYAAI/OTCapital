# StitchAdapter integrates the Stitch open-banking provider (South Africa) into
# the OTCapital provider framework.
#
# Registration: Provider::Factory.register("StitchAccount", self) ensures that
# whenever a StitchAccount is synced the framework routes to this adapter.
class Provider::StitchAdapter < Provider::Base
  include Provider::Syncable
  include Provider::InstitutionMetadata

  Provider::Factory.register("StitchAccount", self)

  def self.supported_account_types
    %w[Depository CreditCard Loan]
  end

  # Returns connection configs visible in the Settings > Providers UI
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
