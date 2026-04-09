# SecurityForecast stores Kronos AI price predictions for a security.
#
# One row per (security, model_version, horizon_days) combination.
# Refreshed daily by KronosForecastJob.
#
# The predictions jsonb column holds an array of hashes:
#   [
#     { "date" => "2026-04-10", "predicted_close" => 185.2,
#       "confidence_low" => 183.0, "confidence_high" => 187.5 },
#     ...
#   ]
#
class SecurityForecast < ApplicationRecord
  belongs_to :security

  validates :ticker,        presence: true
  validates :model_version, presence: true
  validates :horizon_days,  presence: true, numericality: { greater_than: 0 }
  validates :generated_at,  presence: true
  validates :predictions,   presence: true

  validates :security_id, uniqueness: { scope: %i[model_version horizon_days] }

  # ---------------------------------------------------------------------------
  # Class methods
  # ---------------------------------------------------------------------------

  # Upsert a complete forecast for a security.
  # Deletes any existing forecast for the same security/model/horizon, then inserts
  # a fresh one. Wrapped in a transaction to avoid a window with no forecast row.
  def self.upsert_forecasts(security:, forecasts:, model_version: "kronos-mini", horizon_days: 7)
    return if forecasts.blank?

    predictions = forecasts.map do |f|
      {
        "date"            => f.date.iso8601,
        "predicted_close" => f.predicted_close,
        "confidence_low"  => f.confidence_low,
        "confidence_high" => f.confidence_high
      }
    end

    transaction do
      where(security: security, model_version: model_version, horizon_days: horizon_days).delete_all

      create!(
        security:      security,
        ticker:        security.ticker,
        model_version: model_version,
        horizon_days:  horizon_days,
        generated_at:  Time.current,
        predictions:   predictions
      )
    end
  end

  # ---------------------------------------------------------------------------
  # Instance helpers
  # ---------------------------------------------------------------------------

  def next_day_prediction
    predictions.first
  end

  def week_prediction
    predictions.last
  end

  # :bullish, :bearish, or :neutral
  def predicted_direction
    latest_price = security.security_prices.order(date: :desc).first&.price
    end_price    = week_prediction&.dig("predicted_close")

    return :neutral if latest_price.nil? || end_price.nil?

    if end_price > latest_price
      :bullish
    elsif end_price < latest_price
      :bearish
    else
      :neutral
    end
  end

  # Percentage change from current close to end-of-horizon prediction.
  def predicted_change_pct
    latest_price = security.security_prices.order(date: :desc).first&.price.to_f
    end_price    = week_prediction&.dig("predicted_close").to_f

    return 0.0 if latest_price.zero? || end_price.zero?

    ((end_price - latest_price) / latest_price * 100).round(2)
  end

  # True if the forecast was generated recently enough to still be useful.
  def fresh?(max_age: 48.hours)
    generated_at >= max_age.ago
  end
end
