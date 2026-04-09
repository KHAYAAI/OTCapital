# KronosForecastJob generates AI price forecasts for a single security
# using the Kronos foundation model microservice.
#
# Runs on the :scheduled queue (low-priority, same as daily market data sync).
# Triggered daily at 06:00 SAST (04:00 UTC) by KronosForecastScheduler.
#
# Prerequisites:
#   - KRONOS_ENABLED=true (otherwise this job exits immediately)
#   - KRONOS_SERVICE_URL pointing to a running Kronos microservice
#   - The security must have at least 30 trading days of price history in Yahoo Finance
#
# Usage:
#   KronosForecastJob.perform_now(Security.find_by(ticker: "AAPL").id)
#   KronosForecastJob.perform_later(security.id)
#
class KronosForecastJob < ApplicationJob
  queue_as :scheduled

  MINIMUM_CANDLES = 30
  LOOKBACK_DAYS   = 120 # fetch 120 calendar days → ~90 trading days of OHLCV

  def perform(security_id)
    return unless kronos_enabled?

    security = Security.find(security_id)

    candles = fetch_ohlcv(security)
    if candles.nil? || candles.size < MINIMUM_CANDLES
      Rails.logger.info("[KronosJob] Skipping #{security.ticker}: only #{candles&.size || 0} candles (need #{MINIMUM_CANDLES})")
      return
    end

    forecasts = run_forecast(security, candles)
    return if forecasts.nil?

    SecurityForecast.upsert_forecasts(security: security, forecasts: forecasts)
    Rails.logger.info("[KronosJob] Saved #{forecasts.size}-day forecast for #{security.ticker}")
  rescue ActiveRecord::RecordNotFound
    Rails.logger.warn("[KronosJob] Security #{security_id} not found, skipping")
  rescue Provider::Kronos::Error => e
    Rails.logger.error("[KronosJob] Kronos service error for #{security_id}: #{e.message}")
  end

  private

    def kronos_enabled?
      ENV["KRONOS_ENABLED"].to_s.downcase == "true"
    end

    def fetch_ohlcv(security)
      result = Provider::YahooFinance.new.fetch_ohlcv(
        symbol:     security.ticker,
        start_date: LOOKBACK_DAYS.days.ago.to_date,
        end_date:   Date.current
      )

      unless result.success?
        Rails.logger.warn("[KronosJob] OHLCV fetch failed for #{security.ticker}: #{result.error&.message}")
        return nil
      end

      result.data
    end

    def run_forecast(security, candles)
      result = Provider::Kronos.new.forecast_prices(
        symbol:  security.ticker,
        candles: candles
      )

      unless result.success?
        Rails.logger.warn("[KronosJob] Forecast failed for #{security.ticker}: #{result.error&.message}")
        return nil
      end

      result.data
    end
end
