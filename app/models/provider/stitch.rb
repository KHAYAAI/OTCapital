# Provider::Stitch wraps the Stitch Money open-banking API for South Africa.
#
# Stitch uses OAuth 2.0 + GraphQL.
# Docs: https://stitch.money/docs
#
# Flow:
# 1. Exchange client_id + client_secret for an app-level access token
# 2. Generate a link token (user consent URL) via GraphQL mutation
# 3. User authorises their bank in Stitch's hosted UI
# 4. Stitch redirects back with a user_interaction_id
# 5. Exchange user_interaction_id for a user token
# 6. Query accounts and transactions via GraphQL using the user token
class Provider::Stitch
  include HTTParty

  BASE_URL    = "https://api.stitch.money".freeze
  TOKEN_URL   = "#{BASE_URL}/connect/token".freeze
  GRAPHQL_URL = "#{BASE_URL}/graphql".freeze

  # Stitch error that carries an HTTP status symbol
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
