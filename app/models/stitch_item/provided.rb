module StitchItem::Provided
  extend ActiveSupport::Concern

  def stitch_provider
    Provider::Stitch.new(
      client_id:     ENV["STITCH_CLIENT_ID"].presence || Rails.application.credentials.dig(:stitch, :client_id),
      client_secret: ENV["STITCH_CLIENT_SECRET"].presence || Rails.application.credentials.dig(:stitch, :client_secret)
    )
  end

  def syncer
    StitchItem::Syncer.new(self)
  end
end
