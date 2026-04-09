# KronosForecastScheduler registers a daily Sidekiq-Cron job that enqueues
# KronosForecastJob for every security currently held by any family.
#
# Runs at 04:00 UTC daily (06:00 SAST) — after overnight market data has synced.
# Only active when KRONOS_ENABLED=true.
#
class KronosForecastScheduler
  JOB_NAME = "kronos_daily_forecast"
  # 04:00 UTC = 06:00 SAST
  DEFAULT_CRON = "0 4 * * *"

  def self.sync!
    if ENV["KRONOS_ENABLED"].to_s.downcase == "true"
      upsert_job
    else
      remove_job
    end
  end

  def self.upsert_job
    job = Sidekiq::Cron::Job.create(
      name:        JOB_NAME,
      cron:        DEFAULT_CRON,
      class:       "KronosBatchForecastJob",
      queue:       "scheduled",
      description: "Enqueues KronosForecastJob for all held securities"
    )

    if job.nil? || (job.respond_to?(:valid?) && !job.valid?)
      error_msg = job.respond_to?(:errors) ? job.errors.to_a.join(", ") : "unknown"
      Rails.logger.error("[KronosScheduler] Failed to create cron job: #{error_msg}")
    else
      Rails.logger.info("[KronosScheduler] Registered cron job: #{DEFAULT_CRON}")
    end
  end

  def self.remove_job
    if (job = Sidekiq::Cron::Job.find(JOB_NAME))
      job.destroy
      Rails.logger.info("[KronosScheduler] Removed cron job")
    end
  end
end
