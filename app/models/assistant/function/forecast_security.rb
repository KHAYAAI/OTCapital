# ForecastSecurity — AI assistant function that returns Kronos price forecasts.
#
# Allows users to ask the AI assistant questions like:
#   "What is the 7-day price forecast for AAPL?"
#   "Will Naspers go up or down this week?"
#   "Show me the forecast for my top holding"
#
# The function reads from the security_forecasts table (populated daily by
# KronosForecastJob). If no forecast exists, it prompts the user to enable
# Kronos or wait for the next daily run.
#
class Assistant::Function::ForecastSecurity < Assistant::Function
  class << self
    def name
      "forecast_security"
    end

    def description
      <<~DESC
        Get an AI price forecast for a security using the Kronos foundation model.
        Returns predicted closing prices for the next 7 trading days with confidence intervals.

        Use this when the user asks questions like:
        - "What is the forecast for AAPL?"
        - "Will [ticker] go up this week?"
        - "What does the AI predict for my [ticker] position?"

        Note: Forecasts are generated daily and may be up to 48 hours old.
        Kronos must be enabled (KRONOS_ENABLED=true) for forecasts to be available.
      DESC
    end
  end

  def call(params = {})
    ticker = params[:ticker].to_s.upcase.strip

    return { error: "Please provide a ticker symbol (e.g. AAPL, NASPERS, BTC-USD)." } if ticker.blank?

    security = Security.where("upper(ticker) = ?", ticker).first
    return { error: "Security '#{ticker}' not found in your portfolio data." } unless security

    forecast = SecurityForecast.find_by(security: security, model_version: "kronos-mini")
                               .presence ||
               SecurityForecast.find_by(security: security, model_version: "kronos-large")

    if forecast.nil?
      return {
        ticker: ticker,
        error: "No Kronos forecast available for #{ticker}. " \
               "Forecasts are generated daily. If this is your first time, " \
               "please ensure KRONOS_ENABLED=true and try again tomorrow."
      }
    end

    unless forecast.fresh?
      return {
        ticker:  ticker,
        warning: "The forecast for #{ticker} is more than 48 hours old (generated #{forecast.generated_at.strftime('%Y-%m-%d %H:%M UTC')}). " \
                 "A fresh forecast will be generated in the next daily run."
      }
    end

    {
      ticker:             ticker,
      security_name:      security.name,
      generated_at:       forecast.generated_at.iso8601,
      model:              forecast.model_version,
      horizon_days:       forecast.horizon_days,
      predicted_direction: forecast.predicted_direction,
      predicted_change_pct: forecast.predicted_change_pct,
      predictions:        forecast.predictions
    }
  end

  def params_schema
    build_schema(
      required:   [ "ticker" ],
      properties: {
        ticker: {
          type:        "string",
          description: "The ticker symbol of the security to forecast (e.g. AAPL, TSLA, BTC-USD, NPN.JO)"
        }
      }
    )
  end
end
