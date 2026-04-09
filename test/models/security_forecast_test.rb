require "test_helper"

class SecurityForecastTest < ActiveSupport::TestCase
  setup do
    @security = securities(:aapl)
    @forecast = security_forecasts(:aapl_forecast)
  end

  # ---------------------------------------------------------------------------
  # Validations
  # ---------------------------------------------------------------------------

  test "valid fixture is valid" do
    assert @forecast.valid?
  end

  test "requires ticker" do
    @forecast.ticker = nil
    assert_not @forecast.valid?
    assert_includes @forecast.errors[:ticker], "can't be blank"
  end

  test "requires model_version" do
    @forecast.model_version = nil
    assert_not @forecast.valid?
  end

  test "requires horizon_days to be positive" do
    @forecast.horizon_days = 0
    assert_not @forecast.valid?
  end

  test "requires generated_at" do
    @forecast.generated_at = nil
    assert_not @forecast.valid?
  end

  test "enforces uniqueness of security per model and horizon" do
    duplicate = SecurityForecast.new(
      security:      @security,
      ticker:        "AAPL",
      model_version: "kronos-mini",
      horizon_days:  7,
      generated_at:  Time.current,
      predictions:   []
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:security_id], "has already been taken"
  end

  # ---------------------------------------------------------------------------
  # upsert_forecasts
  # ---------------------------------------------------------------------------

  test "upsert_forecasts creates a new forecast row" do
    security = securities(:msft)
    forecasts = [
      Provider::Kronos::Forecast.new(
        date:             Date.current + 1,
        predicted_close:  410.0,
        confidence_low:   405.0,
        confidence_high:  415.0
      )
    ]

    # Remove existing MSFT forecast so we can test create path
    SecurityForecast.where(security: security).delete_all

    assert_difference "SecurityForecast.count", 1 do
      SecurityForecast.upsert_forecasts(security: security, forecasts: forecasts)
    end

    saved = SecurityForecast.find_by!(security: security, model_version: "kronos-mini")
    assert_equal "MSFT", saved.ticker
    assert_equal 1, saved.predictions.size
    assert_equal "410.0", saved.predictions.first["predicted_close"].to_s
  end

  test "upsert_forecasts replaces an existing forecast" do
    new_forecasts = [
      Provider::Kronos::Forecast.new(
        date:             Date.current + 1,
        predicted_close:  200.0,
        confidence_low:   195.0,
        confidence_high:  205.0
      )
    ]

    assert_no_difference "SecurityForecast.count" do
      SecurityForecast.upsert_forecasts(security: @security, forecasts: new_forecasts)
    end

    saved = SecurityForecast.find_by!(security: @security, model_version: "kronos-mini")
    assert_equal 200.0, saved.predictions.first["predicted_close"]
  end

  test "upsert_forecasts is a no-op when forecasts is blank" do
    assert_no_difference "SecurityForecast.count" do
      SecurityForecast.upsert_forecasts(security: @security, forecasts: [])
    end
  end

  # ---------------------------------------------------------------------------
  # Instance helpers
  # ---------------------------------------------------------------------------

  test "next_day_prediction returns first prediction" do
    assert_equal @forecast.predictions.first, @forecast.next_day_prediction
  end

  test "week_prediction returns last prediction" do
    assert_equal @forecast.predictions.last, @forecast.week_prediction
  end

  test "fresh? returns true when generated recently" do
    @forecast.generated_at = 1.hour.ago
    assert @forecast.fresh?
  end

  test "fresh? returns false when forecast is too old" do
    @forecast.generated_at = 3.days.ago
    assert_not @forecast.fresh?
  end

  test "predicted_direction returns :bullish when end price is higher" do
    # AAPL fixture has predicted_close of 188 at end of horizon
    # Make sure current price is lower
    @security.security_prices.create!(
      date: Date.current,
      price: 180.0,
      currency: "USD"
    )
    assert_equal :bullish, @forecast.predicted_direction
  end
end
