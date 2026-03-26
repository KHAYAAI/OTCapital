# Represents a Stitch open-banking connection for a South African family.
# One StitchItem = one bank connection (one consent grant).
# A family can have multiple StitchItems (one per bank).
class StitchItem < ApplicationRecord
  include Syncable, Provided, Unlinking

  enum :status, { good: "good", requires_update: "requires_update" }, default: :good

  belongs_to :family
  has_many :stitch_accounts, dependent: :destroy
  has_many :accounts, through: :stitch_accounts

  validates :name, presence: true

  scope :active,    -> { where(scheduled_for_deletion: false) }
  scope :syncable,  -> { active }
  scope :ordered,   -> { order(created_at: :desc) }
  scope :needs_update, -> { where(status: :requires_update) }

  def destroy_later
    update!(scheduled_for_deletion: true)
    DestroyJob.perform_later(self)
  end

  def token_valid?
    token_id.present? && (token_expires_at.nil? || token_expires_at > Time.current)
  end

  def display_name
    name.presence || "Stitch Connection"
  end
end
