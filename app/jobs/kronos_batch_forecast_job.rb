# KronosBatchForecastJob is the cron-triggered entry point.
# It finds all unique securities currently held by any family and
# enqueues an individual KronosForecastJob for each one.
#
# This keeps the cron job lightweight and lets individual security
# forecasts fail in isolation without blocking others.
#
class KronosBatchForecastJob < ApplicationJob
  queue_as :scheduled

  def perform
    return unless ENV["KRONOS_ENABLED"].to_s.downcase == "true"

    # Find all distinct securities that appear in at least one holding
    security_ids = Holding.joins(:security)
                          .where("holdings.date >= ?", 30.days.ago.to_date)
                          .distinct
                          .pluck(:security_id)

    Rails.logger.info("[KronosBatch] Enqueuing forecasts for #{security_ids.size} securities")

    security_ids.each do |id|
      KronosForecastJob.perform_later(id)
    end
  end
end
