# frozen_string_literal: true

# CORS configuration for API access from mobile clients and other external apps.
#
# Allowed origins are driven by environment variables so each deployment can
# lock down exactly which domains/apps are permitted.
#
# Environment variables:
#   CORS_ORIGINS        — comma-separated list of allowed web origins
#                         e.g. "https://app.otcapital.co.za,https://admin.otcapital.co.za"
#                         Defaults to APP_DOMAIN if set, otherwise localhost:3000 (dev only).
#   APP_DOMAIN          — primary host, used as fallback origin.
#
# In production you MUST set CORS_ORIGINS (or APP_DOMAIN) to avoid the
# wildcard fallback.  The mobile app (otcapital://) is allowed via the
# "null" origin that native WebViews send.

def cors_origins
  if ENV["CORS_ORIGINS"].present?
    ENV["CORS_ORIGINS"].split(",").map(&:strip)
  elsif ENV["APP_DOMAIN"].present?
    [ "https://#{ENV['APP_DOMAIN']}" ]
  else
    # Development/test fallback only — never reaches production if APP_DOMAIN is set
    [ "http://localhost:3000", "http://localhost:4000" ]
  end
end

Rails.application.config.middleware.insert_before 0, Rack::Cors do
  allow do
    # Allowed web origins (configured via CORS_ORIGINS or APP_DOMAIN)
    origins(*cors_origins)

    resource "/api/*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: %w[X-Request-Id X-Runtime],
      max_age: 86400

    resource "/oauth/*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: %w[X-Request-Id X-Runtime],
      max_age: 86400

    resource "/sessions/*",
      headers: :any,
      methods: %i[get post delete options head],
      expose: %w[X-Request-Id X-Runtime],
      max_age: 86400
  end

  # Native mobile app: WebViews send Origin: null — allow it explicitly for OAuth/API
  allow do
    origins "null"

    resource "/api/*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: %w[X-Request-Id X-Runtime],
      max_age: 86400

    resource "/oauth/*",
      headers: :any,
      methods: %i[get post put patch delete options head],
      expose: %w[X-Request-Id X-Runtime],
      max_age: 86400
  end
end
