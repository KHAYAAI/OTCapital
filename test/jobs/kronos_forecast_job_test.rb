require "test_helper"

class KronosForecastJobTest < ActiveJob::TestCase
  setup do
    @security  = securities(:aapl)
    @candles   = build_candles(60)
    @forecasts = [
      Provider::Kronos::Forecast.new(
        date: Date.current + 1, predicted_close: 185.0,
        confidence_low: 183.0, confidence_high: 187.0
      )
    ]
  end

  test "does nothing when KRONOS_ENABLED is not set" do
    with_env("KRONOS_ENABLED" => nil) do
      SecurityForecast.expects(:upsert_forecasts).never
      KronosForecastJob.perform_now(@security.id)
    end
  end

  test "does nothing when KRONOS_ENABLED is false" do
    with_env("KRONOS_ENABLED" => "false") do
      SecurityForecast.expects(:upsert_forecasts).never
      KronosForecastJob.perform_now(@security.id)
    end
  end

  test "fetches OHLCV and upserts forecast when enabled" do
    with_env("KRONOS_ENABLED" => "true") do
      ohlcv_result    = Provider::Response.new(success?: true, data: @candles, error: nil)
      forecast_result = Provider::Response.new(success?: true, data: @forecasts, error: nil)

      Provider::YahooFinance.any_instance.expects(:fetch_ohlcv).returns(ohlcv_result)
      Provider::Kronos.any_instance.expects(:forecast_prices).returns(forecast_result)
      SecurityForecast.expects(:upsert_forecasts).with(security: @security, forecasts: @forecasts).once

      KronosForecastJob.perform_now(@security.id)
    end
  end

  test "skips when OHLCV fetch fails" do
    with_env("KRONOS_ENABLED" => "true") do
      failed_result = Provider::Response.new(success?: false, data: nil, error: Provider::YahooFinance::Error.new("timeout"))

      Provider::YahooFinance.any_instance.expects(:fetch_ohlcv).returns(failed_result)
      Provider::Kronos.any_instance.expects(:forecast_prices).never
      SecurityForecast.expects(:upsert_forecasts).never

      KronosForecastJob.perform_now(@security.id)
    end
  end

  test "skips when fewer than 30 candles returned" do
    with_env("KRONOS_ENABLED" => "true") do
      few_candles  = build_candles(10)
      ohlcv_result = Provider::Response.new(success?: true, data: few_candles, error: nil)

      Provider::YahooFinance.any_instance.expects(:fetch_ohlcv).returns(ohlcv_result)
      Provider::Kronos.any_instance.expects(:forecast_prices).never

      KronosForecastJob.perform_now(@security.id)
    end
  end

  test "handles RecordNotFound gracefully" do
    with_env("KRONOS_ENABLED" => "true") do
      assert_nothing_raised do
        KronosForecastJob.perform_now("00000000-0000-0000-0000-000000000000")
      end
    end
  end

  private

    def build_candles(count)
      count.times.map do |i|
        Provider::SecurityConcept::OHLCVCandle.new(
          date: count.days.ago.to_date + i, open: 180.0, high: 185.0,
          low: 178.0, close: 182.0, volume: 50_000_000
        )
      end
    end

    def with_env(vars)
      original = vars.keys.each_with_object({}) { |k, h| h[k] = ENV[k] }
      vars.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
      yield
    ensure
      original.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
    end
end
