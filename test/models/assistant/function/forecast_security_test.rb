require "test_helper"

class Assistant::Function::ForecastSecurityTest < ActiveSupport::TestCase
  setup do
    @user     = users(:empty)
    @function = Assistant::Function::ForecastSecurity.new(@user)
    @forecast = security_forecasts(:aapl_forecast)
  end

  test "returns forecast data when ticker has a fresh forecast" do
    result = @function.call(ticker: "AAPL")

    assert_equal "AAPL",         result[:ticker]
    assert_equal "kronos-mini",  result[:model]
    assert_equal 7,              result[:horizon_days]
    assert_kind_of Array,        result[:predictions]
    assert result[:predictions].any?
  end

  test "is case-insensitive for ticker lookup" do
    result = @function.call(ticker: "aapl")
    assert_equal "AAPL", result[:ticker]
    assert_nil result[:error]
  end

  test "returns error when ticker is blank" do
    result = @function.call(ticker: "")
    assert result[:error].present?
    assert_match(/ticker/, result[:error].downcase)
  end

  test "returns error when security is not found" do
    result = @function.call(ticker: "NOTREAL")
    assert result[:error].present?
    assert_match(/not found/i, result[:error])
  end

  test "returns error when no forecast exists for the security" do
    # MSFT fixture has a stale forecast (3 days old) — clear it to test no-forecast case
    SecurityForecast.where(security: securities(:msft)).delete_all

    result = @function.call(ticker: "MSFT")
    assert result[:error].present?
    assert_match(/no kronos forecast/i, result[:error])
  end

  test "returns warning when forecast is stale" do
    stale = security_forecasts(:msft_forecast)
    # msft_forecast fixture generated_at is 3 days ago (stale)
    result = @function.call(ticker: "MSFT")
    assert result[:warning].present?
    assert_match(/48 hours/i, result[:warning])
  end

  test "function name is forecast_security" do
    assert_equal "forecast_security", Assistant::Function::ForecastSecurity.name
  end

  test "params_schema requires ticker" do
    schema = @function.params_schema
    assert_includes schema.dig(:required) || schema["required"], "ticker"
  end
end
