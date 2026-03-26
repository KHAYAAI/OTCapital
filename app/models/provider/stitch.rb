# =============================================================================
# Provider::Stitch — South African Open Banking API Client
# =============================================================================
#
# WHAT IS STITCH?
# ---------------
# Stitch Money (https://stitch.money) is South Africa's leading open-banking
# aggregator. It provides OAuth-authenticated access to bank accounts at FNB,
# Standard Bank, ABSA, Nedbank, Capitec, Discovery Bank, Investec, TymeBank
# and others — covering the majority of SA retail banking.
#
# CREDENTIAL SETUP (dev/production)
# -----------------------------------
# Obtain credentials at https://stitch.money/docs/get-started
# Then set in your environment OR Rails credentials file:
#
#   ENV vars (recommended for Docker/Heroku/Render):
#     STITCH_CLIENT_ID=your_client_id
#     STITCH_CLIENT_SECRET=your_client_secret
#
#   Rails credentials (rails credentials:edit):
#     stitch:
#       client_id: your_client_id
#       client_secret: your_client_secret
#
# The controller (StitchItemsController#build_stitch_provider) prefers ENV
# vars but falls back to credentials automatically.
#
# OAUTH FLOW (5 steps)
# --------------------
# Step 1 → [app-level]  POST /connect/token (client_credentials grant)
#           Returns: app_token (used only to create link tokens)
#
# Step 2 → [app-level]  GraphQL mutation: clientInitiateUserLinkToken
#           Returns: link_url (redirect the user here), nonce
#           The link_url opens Stitch's hosted consent UI in the user's browser.
#
# Step 3 → [user action] User logs in to their bank inside Stitch's UI and
#           approves the connection. Stitch redirects to our callback URL
#           (/stitch_items/callback) with a `user_interaction_id` param.
#
# Step 4 → [app-level]  POST /connect/token (authorization_code grant)
#           Exchange user_interaction_id → user_token (scoped to that user's bank)
#
# Step 5 → [user-level] GraphQL queries with user_token: get_accounts,
#           get_transactions
#
# IMPORTANT: user_interaction_id is SINGLE-USE. Store it in stitch_items
# immediately on callback and exchange it for a user_token before it expires.
# User tokens have a longer lifetime and should be refreshed as needed.
#
# ARCHITECTURE NOTE
# -----------------
# This class is a pure HTTP client — no Rails models, no side-effects.
# It is instantiated by StitchItem::Provided#stitch_provider and by
# StitchItemsController#build_stitch_provider.
# The adapter (Provider::StitchAdapter) wires this into the Provider::Factory
# registry so the existing sync infrastructure works without modification.
#
class Provider::Stitch
  include HTTParty

  BASE_URL    = "https://api.stitch.money".freeze
  TOKEN_URL   = "#{BASE_URL}/connect/token".freeze
  GRAPHQL_URL = "#{BASE_URL}/graphql".freeze

  # StitchError is raised for all non-2xx responses and GraphQL error arrays.
  # `reason` is a symbol you can pattern-match on in rescue clauses:
  #   :unauthorized   → credentials wrong / token expired — re-authorise
  #   :forbidden      → scope not granted — check Stitch dashboard permissions
  #   :unprocessable  → bad request body — check your GraphQL variables
  #   :graphql_error  → Stitch returned data but with errors[] array
  #   :api_error      → catch-all for unexpected status codes
  #   :auth_failed    → token endpoint returned no access_token
  #   :link_token_failed → link token mutation returned no result
  class StitchError < StandardError
    attr_reader :reason
    def initialize(msg, reason = :unknown)
      super(msg)
      @reason = reason
    end
  end

  def initialize(client_id:, client_secret:)
    @client_id     = client_id
    @client_secret = client_secret
  end

  # ---------------------------------------------------------------------------
  # App-level token (client credentials) — used to generate link tokens
  # ---------------------------------------------------------------------------
  def app_token
    @app_token ||= fetch_app_token
  end

  # ---------------------------------------------------------------------------
  # Generate a Stitch Link token so the user can connect their bank account
  #
  # @param redirect_uri [String] Where Stitch redirects after consent
  # @param state        [String] Opaque state value you generate (CSRF protection)
  # @return [Hash] { :link_url, :nonce }
  # ---------------------------------------------------------------------------
  def create_link_token(redirect_uri:, state:)
    mutation = <<~GQL
      mutation CreateLinkToken($input: ClientInitiateUserLinkTokenInput!) {
        clientInitiateUserLinkToken(input: $input) {
          linkUrl
          nonce
        }
      }
    GQL

    variables = {
      input: {
        redirectUri: redirect_uri,
        state: state,
        country: "ZA",
        linkPaymentConsent: false
      }
    }

    data = graphql(mutation, variables, token: app_token)
    result = data.dig("clientInitiateUserLinkToken")
    raise StitchError.new("Failed to create link token: #{data.inspect}", :link_token_failed) unless result

    { link_url: result["linkUrl"], nonce: result["nonce"] }
  end

  # ---------------------------------------------------------------------------
  # Exchange a user_interaction_id for a user-scoped access token
  #
  # @param user_interaction_id [String] Value from the Stitch redirect callback
  # @param redirect_uri        [String] Must match what was used in create_link_token
  # @return [Hash] { :access_token, :token_type, :expires_in, :id_token }
  # ---------------------------------------------------------------------------
  def exchange_user_token(user_interaction_id:, redirect_uri:)
    response = self.class.post(
      TOKEN_URL,
      body: {
        grant_type:           "authorization_code",
        client_id:            @client_id,
        client_secret:        @client_secret,
        code:                 user_interaction_id,
        redirect_uri:         redirect_uri
      }
    )

    handle_response(response)
  end

  # ---------------------------------------------------------------------------
  # Fetch connected bank accounts for a user
  #
  # @param user_token [String] The user-scoped access token
  # @return [Array<Hash>] List of bank account objects
  # ---------------------------------------------------------------------------
  def get_accounts(user_token:)
    query = <<~GQL
      query GetAccounts {
        user {
          bankAccounts {
            id
            name
            accountType
            accountNumber
            currency
            currentBalance
            availableBalance
            bankId
            bankName
          }
        }
      }
    GQL

    data = graphql(query, {}, token: user_token)
    data.dig("user", "bankAccounts") || []
  end

  # ---------------------------------------------------------------------------
  # Fetch transactions for a bank account
  #
  # @param user_token [String] User-scoped access token
  # @param account_id [String] Stitch bankAccount.id
  # @param from_date  [Date]   Earliest transaction date (optional)
  # @return [Array<Hash>] List of transaction objects
  # ---------------------------------------------------------------------------
  def get_transactions(user_token:, account_id:, from_date: nil)
    query = <<~GQL
      query GetTransactions($accountId: ID!, $fromDate: Date) {
        user {
          bankAccount(id: $accountId) {
            transactions(filter: { fromDate: $fromDate }) {
              edges {
                node {
                  id
                  amount
                  date
                  description
                  status
                  direction
                  reference
                  currency
                  runningBalance
                }
              }
            }
          }
        }
      }
    GQL

    variables = { accountId: account_id, fromDate: from_date&.iso8601 }.compact
    data = graphql(query, variables, token: user_token)
    edges = data.dig("user", "bankAccount", "transactions", "edges") || []
    edges.map { |e| e["node"] }
  end

  private

    def fetch_app_token
      response = self.class.post(
        TOKEN_URL,
        body: {
          grant_type:    "client_credentials",
          client_id:     @client_id,
          client_secret: @client_secret,
          scope:         "client_imageupload"
        }
      )

      result = handle_response(response)
      result["access_token"] or raise StitchError.new("No access_token in response", :auth_failed)
    end

    # Execute a GraphQL request against the Stitch API
    def graphql(query, variables, token:)
      response = self.class.post(
        GRAPHQL_URL,
        headers: {
          "Authorization" => "Bearer #{token}",
          "Content-Type"  => "application/json"
        },
        body: { query: query, variables: variables }.to_json
      )

      parsed = handle_response(response)

      if parsed["errors"].present?
        raise StitchError.new("GraphQL errors: #{parsed['errors'].inspect}", :graphql_error)
      end

      parsed["data"] || {}
    end

    def handle_response(response)
      case response.code
      when 200, 201
        response.parsed_response
      when 401
        raise StitchError.new("Stitch authentication failed (401)", :unauthorized)
      when 403
        raise StitchError.new("Stitch access forbidden (403)", :forbidden)
      when 422
        raise StitchError.new("Stitch unprocessable entity: #{response.body}", :unprocessable)
      else
        raise StitchError.new("Stitch API error (#{response.code}): #{response.body}", :api_error)
      end
    end
end
