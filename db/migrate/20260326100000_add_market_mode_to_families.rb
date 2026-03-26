# Adds market_mode to families so each family can independently choose
# South Africa (primary) or Global (US/EU) banking infrastructure.
#
# Default is "sa" — South Africa first. Existing families (before this
# migration) will also receive "sa" via the column default. To bulk-update
# any pre-existing US families after running migrations:
#
#   Family.where(country: "US").update_all(market_mode: "global")
#
# Valid values: "sa" | "global"
# Enforced by Family::MARKET_MODES and validates :market_mode, inclusion:.
class AddMarketModeToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :market_mode, :string, default: "sa", null: false
  end
end
