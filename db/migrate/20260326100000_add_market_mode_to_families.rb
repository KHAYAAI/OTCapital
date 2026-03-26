class AddMarketModeToFamilies < ActiveRecord::Migration[7.2]
  def change
    add_column :families, :market_mode, :string, default: "sa", null: false
  end
end
