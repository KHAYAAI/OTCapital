# =============================================================================
# StitchItemsController — Manages the Stitch SA open-banking OAuth flow
# =============================================================================
#
# FULL USER JOURNEY (happy path)
# --------------------------------
# 1. GET  /stitch_items/new
#    User opens "Connect a bank account" modal from Settings → Providers.
#    They enter an optional friendly name (e.g. "My FNB").
#
# 2. POST /stitch_items (create)
#    - Saves a new StitchItem with status=good, no token yet.
#    - Calls Provider::Stitch#create_link_token to get a Stitch-hosted URL.
#    - Redirects the user to that URL (Stitch's consent UI, external).
#    - The StitchItem.id is passed as `state` so we can find it on callback.
#
# 3. GET /stitch_items/callback
#    Stitch redirects back here with:
#      ?id=<user_interaction_id>&state=<stitch_item.id>
#    - Finds the pending StitchItem by state param.
#    - Stores the user_interaction_id on the StitchItem.
#    - Redirects to setup_accounts.
#    NOTE: CSRF verification is skipped for this action — Stitch is the
#    initiator of this GET, not a form submission from our app.
#
# 4. GET /stitch_items/:id/setup_accounts
#    - Exchanges user_interaction_id → user_token via Stitch API.
#    - Fetches the list of bank accounts available under this connection.
#    - Renders a checklist for the user to select which accounts to link.
#
# 5. POST /stitch_items/:id/complete_account_setup
#    - For each selected account:
#        • If new: creates an OTCapital Account record (ZAR, correct type)
#        • Creates/updates the StitchAccount join record
#        • Calls upsert_stitch_snapshot! to store the latest metadata
#    - Redirects to Settings → Providers with a success notice.
#
# ERROR HANDLING
# --------------
# Provider::Stitch::StitchError is caught at each step. On error we redirect
# to settings_providers_path with an alert rather than showing a broken page.
# The error reason symbol (e.reason) can be used for more granular handling
# if needed (e.g. re-prompting auth on :unauthorized).
#
# ENVIRONMENT / CREDENTIALS REQUIRED
# ------------------------------------
#   STITCH_CLIENT_ID     (ENV or credentials: stitch.client_id)
#   STITCH_CLIENT_SECRET (ENV or credentials: stitch.client_secret)
#
class StitchItemsController < ApplicationController
  before_action :set_stitch_item, only: %i[update destroy sync setup_accounts complete_account_setup]
  skip_before_action :verify_authenticity_token, only: [:callback]

  def new
    @stitch_item = Current.family.stitch_items.build
    @accountable_type = params[:accountable_type]
  end

  def create
    @stitch_item = Current.family.stitch_items.build(stitch_item_params)
    @stitch_item.name ||= "Stitch Connection"

    if @stitch_item.save
      redirect_url = build_redirect_url
      stitch = build_stitch_provider
      link_data = stitch.create_link_token(
        redirect_uri: redirect_url,
        state:        @stitch_item.id
      )
      redirect_to link_data[:link_url], allow_other_host: true
    else
      render :new, status: :unprocessable_entity
    end
  rescue Provider::Stitch::StitchError => e
    Rails.logger.error("Stitch link token error: #{e.message}")
    redirect_to settings_providers_path, alert: t(".stitch_link_failed")
  end

  # Stitch redirects here after user authorises their bank
  def callback
    user_interaction_id = params[:id] || params[:code]
    stitch_item_id      = params[:state]

    @stitch_item = Current.family.stitch_items.find_by(id: stitch_item_id)

    if @stitch_item.nil?
      redirect_to settings_providers_path, alert: t(".item_not_found") and return
    end

    if user_interaction_id.blank?
      @stitch_item.update!(status: :requires_update)
      redirect_to settings_providers_path, alert: t(".authorization_failed") and return
    end

    @stitch_item.update!(user_interaction_id: user_interaction_id)
    redirect_to setup_accounts_stitch_item_path(@stitch_item)
  end

  def setup_accounts
    stitch = build_stitch_provider
    user_token = exchange_user_token(stitch)
    @accounts = stitch.get_accounts(user_token: user_token)
    @existing_stitch_account_ids = @stitch_item.stitch_accounts.pluck(:remote_id)
  rescue Provider::Stitch::StitchError => e
    Rails.logger.error("Stitch setup_accounts error: #{e.message}")
    redirect_to settings_providers_path, alert: t(".fetch_accounts_failed")
  end

  def complete_account_setup
    stitch = build_stitch_provider
    user_token = exchange_user_token(stitch)
    remote_accounts = stitch.get_accounts(user_token: user_token)

    selected_ids = Array(params[:account_ids])
    selected_accounts = remote_accounts.select { |a| selected_ids.include?(a["id"]) }

    selected_accounts.each do |remote_acct|
      stitch_acct = @stitch_item.stitch_accounts.find_or_initialize_by(remote_id: remote_acct["id"])

      if stitch_acct.new_record?
        account = Current.family.accounts.create!(
          name:        remote_acct["name"] || "#{remote_acct['bankName']} Account",
          accountable_type: stitch_acct.class::SA_ACCOUNT_TYPE_MAP[remote_acct["accountType"]] || "Depository",
          currency:    remote_acct["currency"].presence || "ZAR",
          balance:     remote_acct["currentBalance"].to_d
        )
        stitch_acct.account = account
      end

      stitch_acct.upsert_stitch_snapshot!(remote_acct)
    end

    redirect_to settings_providers_path, notice: t(".success")
  rescue Provider::Stitch::StitchError => e
    Rails.logger.error("Stitch complete_account_setup error: #{e.message}")
    redirect_to settings_providers_path, alert: t(".link_failed")
  end

  def update
    if @stitch_item.update(stitch_item_params)
      redirect_to settings_providers_path, notice: t(".success"), status: :see_other
    else
      redirect_to settings_providers_path, alert: @stitch_item.errors.full_messages.join(", "), status: :unprocessable_entity
    end
  end

  def destroy
    @stitch_item.destroy_later
    redirect_to settings_providers_path, notice: t(".success"), status: :see_other
  end

  def sync
    @stitch_item.sync_later
    redirect_to settings_providers_path, notice: t(".sync_queued"), status: :see_other
  end

  def select_existing_account
    @stitch_item = Current.family.stitch_items.new
    @accounts = Current.family.accounts.where(id: params[:account_id])
  end

  def link_existing_account
    @stitch_item = Current.family.stitch_items.find_or_create_by!(name: "Stitch Connection")
    account = Current.family.accounts.find(params[:account_id])
    stitch_acct = @stitch_item.stitch_accounts.find_or_initialize_by(remote_id: "existing_#{account.id}")
    stitch_acct.account = account
    stitch_acct.currency = account.currency
    stitch_acct.save!
    redirect_to settings_providers_path, notice: t(".success"), status: :see_other
  end

  private

    def set_stitch_item
      @stitch_item = Current.family.stitch_items.find(params[:id])
    end

    def stitch_item_params
      params.require(:stitch_item).permit(:name)
    end

    def build_stitch_provider
      Provider::Stitch.new(
        client_id:     ENV["STITCH_CLIENT_ID"].presence || Rails.application.credentials.dig(:stitch, :client_id),
        client_secret: ENV["STITCH_CLIENT_SECRET"].presence || Rails.application.credentials.dig(:stitch, :client_secret)
      )
    end

    def build_redirect_url
      callback_stitch_items_url
    end

    def exchange_user_token(stitch)
      stitch.exchange_user_token(
        user_interaction_id: @stitch_item.user_interaction_id,
        redirect_uri: build_redirect_url
      ).then { |r| r["access_token"] }
    end
end
