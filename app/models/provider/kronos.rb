# Provider::Kronos — HTTP client for the Kronos AI forecasting microservice.
#
# Kronos is an open-source foundation model for financial candlestick (OHLCV) data,
# trained on 12B+ K-lines from 45 global exchanges. AAAI 2026.
# https://github.com/shiyu-coder/Kronos
#
# This provider is a thin HTTP wrapper that sends OHLCV data to the Python
# FastAPI microservice (services/kronos/) and returns structured Forecast objects.
#
# Configuration:
#   KRONOS_SERVICE_URL  — base URL of the microservice (default: http://kronos:5000)
#   KRONOS_MODEL        — model size: "mini" (default), "small", or "large"
#
# Usage:
#   provider = Provider::Kronos.new
#   candles  = Provider::YahooFinance.new.fetch_ohlcv(symbol: "AAPL", ...).data
#   result   = provider.forecast_prices(symbol: "AAPL", candles: candles)
#   result.data  # => [Provider::Kronos::Forecast(...), ...]
#
class Provider::Kronos < Provider
  Error = Class.new(Provider::Error)

  # One predicted OHLCV day from the Kronos model.
  Forecast = Data.define(:date, :predicted_close, :confidence_low, :confidence_high)

  DEFAULT_SERVICE_URL = "http://kronos:5000"
  DEFAULT_HORIZON     = 7
  REQUEST_TIMEOUT     = 120 # seconds — model inference can be slow on CPU

  def initialize(
    service_url: ENV.fetch("KRONOS_SERVICE_URL", DEFAULT_SERVICE_URL),
    model_size:  ENV.fetch("KRONOS_MODEL", "mini")
  )
    @service_url = service_url.chomp("/")
    @model_size  = model_size
  end

  # POST OHLCV data to the Kronos microservice and return Forecast structs.
  #
  # @param symbol  [String]              e.g. "AAPL", "NASPERS", "BTC-USD"
  # @param candles [Array<OHLCVCandle>]  from Provider::YahooFinance#fetch_ohlcv
  # @param horizon [Integer]             trading days to forecast (default: 7)
  # @return [Provider::Response] with data: Array<Forecast>
  def forecast_prices(symbol:, candles:, horizon: DEFAULT_HORIZON)
    with_provider_response do
      raise Error, "Need at least 30 OHLCV candles, got #{candles.size}" if candles.size < 30

      payload = {
        symbol:     symbol.upcase,
        ohlcv:      candles.map { |c| serialize_candle(c) },
        horizon:    horizon,
        model_size: @model_size
      }.to_json

      response = client.post("/forecast") do |req|
        req.headers["Content-Type"] = "application/json"
        req.body = payload
      end

      parsed = JSON.parse(response.body)

      if response.status != 200
        raise Error, "Kronos service error (#{response.status}): #{parsed.dig('detail') || parsed.inspect}"
      end

      parsed["predictions"].map do |p|
        Forecast.new(
          date:             Date.parse(p["date"]),
          predicted_close:  p["predicted_close"].to_f,
          confidence_low:   p["confidence_low"].to_f,
          confidence_high:  p["confidence_high"].to_f
        )
      end
    end
  end

  # Lightweight health check — returns true if the microservice is reachable
  # and the model is loaded.
  def healthy?
    response = client.get("/health")
    data = JSON.parse(response.body)
    data["status"] == "ok"
  rescue
    false
  end

  private

    def serialize_candle(candle)
      {
        date:   candle.date.iso8601,
        open:   candle.open.to_f,
        high:   candle.high.to_f,
        low:    candle.low.to_f,
        close:  candle.close.to_f,
        volume: candle.volume.to_i
      }
    end

    def client
      @client ||= Faraday.new(url: @service_url) do |f|
        f.options.timeout      = REQUEST_TIMEOUT
        f.options.open_timeout = 10
        f.adapter Faraday.default_adapter
      end
    end
end
