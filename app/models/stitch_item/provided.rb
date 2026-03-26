# StitchItem::Provided — builds the API client and syncer for a StitchItem.
#
# Follows the same "Provided" pattern used by every other item model
# (MercuryItem::Provided, LunchflowItem::Provided, etc.) to keep the
# model file thin and the provider-construction logic isolated.
#
# CREDENTIAL RESOLUTION ORDER
#   1. STITCH_CLIENT_ID / STITCH_CLIENT_SECRET environment variables
#   2. Rails credentials file: stitch.client_id / stitch.client_secret
#
# The same order is used in StitchItemsController#build_stitch_provider —
# they must stay in sync if you change either.
module StitchItem::Provided
  extend ActiveSupport::Concern

  # Build a Provider::Stitch API client using app-level Stitch credentials.
  # Note: this client is stateless — create a new instance per call.
  def stitch_provider
    Provider::Stitch.new(
      client_id:     ENV["STITCH_CLIENT_ID"].presence || Rails.application.credentials.dig(:stitch, :client_id),
      client_secret: ENV["STITCH_CLIENT_SECRET"].presence || Rails.application.credentials.dig(:stitch, :client_secret)
    )
  end

  # Returns the syncer used by the Syncable background job infrastructure.
  # Called by SyncJob (or any code that does stitch_item.sync_later).
  def syncer
    StitchItem::Syncer.new(self)
  end
end
