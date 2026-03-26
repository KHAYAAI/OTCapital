# =============================================================================
# StitchItem — One Stitch open-banking connection for a Family
# =============================================================================
#
# CONCEPT
# -------
# One StitchItem represents one consent grant with Stitch. A family that banks
# at FNB AND Standard Bank will have TWO StitchItems, each with their own
# user_interaction_id and user token.
#
# A StitchItem has many StitchAccounts (one per bank account within that
# consent grant), and each StitchAccount is linked to one OTCapital Account.
#
# DB COLUMNS (see migration 20260326100001_create_stitch_tables)
# --------------------------------------------------------------
#   name                 — user-facing label, e.g. "My FNB Accounts"
#   token_id             — Stitch link token ID (used during the OAuth flow)
#   user_interaction_id  — The code returned from Stitch's callback URL.
#                          Exchange this for a user token via
#                          Provider::Stitch#exchange_user_token.
#                          CRITICAL: store this immediately on callback — it
#                          is single-use and expires quickly.
#   status               — "good" or "requires_update" (re-auth needed)
#   scheduled_for_deletion — soft-delete flag; DestroyJob handles cleanup
#   token_expires_at     — optional: when the user token expires
#   raw_payload          — JSON dump of the last Stitch API response for debugging
#
# CONCERNS
# --------
#   Syncable   — adds sync_later (background job), last_synced_at tracking
#   Provided   — StitchItem::Provided — adds #stitch_provider and #syncer
#   Unlinking  — StitchItem::Unlinking — adds #unlink_all! for cleanup
#
# LIFECYCLE
# ---------
#   Create  → StitchItemsController#create (saves item, redirects to Stitch)
#   Callback → StitchItemsController#callback (stores user_interaction_id)
#   Setup    → StitchItemsController#setup_accounts / #complete_account_setup
#   Sync     → StitchItem::Syncer#sync_data (background via Syncable#sync_later)
#   Delete   → destroy_later (soft-delete → DestroyJob → actual destroy)
#
class StitchItem < ApplicationRecord
  include Syncable, Provided, Unlinking

  # "good" = connected and working
  # "requires_update" = consent expired or revoked; user must re-authorise
  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  belongs_to :family
  has_many :stitch_accounts, dependent: :destroy
  has_many :accounts, through: :stitch_accounts

  validates :name, presence: true

  scope :active,       -> { where(scheduled_for_deletion: false) }
  scope :syncable,     -> { active }
  scope :ordered,      -> { order(created_at: :desc) }
  scope :needs_update, -> { where(status: :requires_update) }

  # Queue a background job to soft-delete this item and all associated data.
  # Use this instead of destroy directly so child records are cleaned up safely.
  def destroy_later
    update!(scheduled_for_deletion: true)
    DestroyJob.perform_later(self)
  end

  # Returns true if the stored Stitch user token is still usable.
  # A nil token_expires_at means "no known expiry" → treated as valid.
  def token_valid?
    token_id.present? && (token_expires_at.nil? || token_expires_at > Time.current)
  end

  def display_name
    name.presence || "Stitch Connection"
  end
end
