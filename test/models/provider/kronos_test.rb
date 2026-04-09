require "test_helper"

class Provider::KronosTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Kronos.new(service_url: "http://kronos-test:5000", model_size: "mini")
    @candles   = build_candles(60) # 60 trading days of OHLCV
  end

  # ---------------------------------------------------------------------------
  # forecast_prices — success path
  # ---------------------------------------------------------------------------

  test "returns Forecast structs on successful response" do
    stub_forecast_response(symbol: "AAPL", predictions: [
      { "date" => "2026-04-10", "predicted_close" => 185.2, "confidence_low" => 183.0, "confidence_high" => 187.5 },
      { "date" => "2026-04-11", "predicted_close" => 186.0, "confidence_low" => 183.5, "confidence_high" => 188.0 }
    ])

    result = @provider.forecast_prices(symbol: "AAPL", candles: @candles)

    assert result.success?
    assert_equal 2, result.data.size

    first = result.data.first
    assert_instance_of Provider::Kronos::Forecast, first
    assert_equal Date.parse("2026-04-10"), first.date
    assert_in_delta 185.2, first.predicted_close, 0.001
    assert_in_delta 183.0, first.confidence_low,  0.001
    assert_in_delta 187.5, first.confidence_high, 0.001
  end

  test "upcases the symbol before sending" do
    stub_forecast_response(symbol: "AAPL", predictions: [])
    result = @provider.forecast_prices(symbol: "aapl", candles: @candles)
    assert result.success?
  end

  # ---------------------------------------------------------------------------
  # forecast_prices — error paths
  # ---------------------------------------------------------------------------

  test "returns failure response when fewer than 30 candles provided" do
    result = @provider.forecast_prices(symbol: "AAPL", candles: build_candles(10))

    assert_not result.success?
    assert_match(/30/, result.error.message)
  end

  test "returns failure response when service returns non-200" do
    stub_request(:post, "http://kronos-test:5000/forecast")
      .to_return(status: 503, body: '{"detail":"Model not ready"}', headers: { "Content-Type" => "application/json" })

    result = @provider.forecast_prices(symbol: "AAPL", candles: @candles)

    assert_not result.success?
    assert_match(/503/, result.error.message)
  end

  test "returns failure response when service is unreachable" do
    stub_request(:post, "http://kronos-test:5000/forecast")
      .to_raise(Faraday::ConnectionFailed.new("connection refused"))

    result = @provider.forecast_prices(symbol: "AAPL", candles: @candles)

    assert_not result.success?
  end

  # ---------------------------------------------------------------------------
  # healthy?
  # ---------------------------------------------------------------------------

  test "healthy? returns true when service responds ok" do
    stub_request(:get, "http://kronos-test:5000/health")
      .to_return(status: 200, body: '{"status":"ok","model":"kronos-mini","model_loaded":true}')

    assert @provider.healthy?
  end

  test "healthy? returns false when service is down" do
    stub_request(:get, "http://kronos-test:5000/health")
      .to_raise(Faraday::ConnectionFailed.new("refused"))

    assert_not @provider.healthy?
  end

  private

    def build_candles(count)
      count.times.map do |i|
        Provider::SecurityConcept::OHLCVCandle.new(
          date:   count.days.ago.to_date + i,
          open:   180.0 + rand(5.0),
          high:   185.0 + rand(5.0),
          low:    178.0 + rand(3.0),
          close:  182.0 + rand(5.0),
          volume: 50_000_000
        )
      end
    end

    def stub_forecast_response(symbol:, predictions:)
      response_body = {
        symbol:       symbol,
        generated_at: Time.current.iso8601,
        model:        "kronos-mini",
        horizon:      predictions.size,
        predictions:  predictions
      }.to_json

      stub_request(:post, "http://kronos-test:5000/forecast")
        .to_return(status: 200, body: response_body, headers: { "Content-Type" => "application/json" })
    end
end
