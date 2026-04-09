module Provider::SecurityConcept
  extend ActiveSupport::Concern

  Security = Data.define(:symbol, :name, :logo_url, :exchange_operating_mic, :country_code)
  SecurityInfo = Data.define(:symbol, :name, :links, :logo_url, :description, :kind, :exchange_operating_mic)
  Price = Data.define(:symbol, :date, :price, :currency, :exchange_operating_mic)

  # OHLCV candlestick data point — used by the Kronos forecasting integration.
  # open/high/low/close are in the security's native currency; volume is share count.
  OHLCVCandle = Data.define(:date, :open, :high, :low, :close, :volume)

  def search_securities(symbol, country_code: nil, exchange_operating_mic: nil)
    raise NotImplementedError, "Subclasses must implement #search_securities"
  end

  def fetch_security_info(symbol:, exchange_operating_mic:)
    raise NotImplementedError, "Subclasses must implement #fetch_security_info"
  end

  def fetch_security_price(symbol:, exchange_operating_mic:, date:)
    raise NotImplementedError, "Subclasses must implement #fetch_security_price"
  end

  def fetch_security_prices(symbol:, exchange_operating_mic:, start_date:, end_date:)
    raise NotImplementedError, "Subclasses must implement #fetch_security_prices"
  end

  # Returns an array of OHLCVCandle for use with the Kronos forecasting model.
  # Providers that do not support OHLCV data will raise NotImplementedError.
  def fetch_ohlcv(symbol:, exchange_operating_mic: nil, start_date:, end_date:)
    raise NotImplementedError, "#{self.class} does not support OHLCV data"
  end
end
