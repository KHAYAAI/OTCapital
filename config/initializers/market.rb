# Market mode configuration for OTCapital
#
# SA (South Africa) is the primary market. Users can switch to "global" mode
# to use the original US/EU-centric providers and defaults.
#
# MARKET_MODE env var: "sa" (default) or "global"
# Families also store their own market_mode preference which overrides the app default.

Rails.application.configure do
  # Default market mode: "sa" for South Africa (primary), "global" for US/EU
  config.x.default_market_mode = ENV.fetch("MARKET_MODE", "sa")
end

# South African bank list used for display in the Stitch integration UI
SA_BANKS = [
  { id: "fnb",               name: "First National Bank (FNB)",   logo: "fnb" },
  { id: "standard_bank",     name: "Standard Bank",               logo: "standard_bank" },
  { id: "absa",              name: "ABSA Bank",                   logo: "absa" },
  { id: "nedbank",           name: "Nedbank",                     logo: "nedbank" },
  { id: "capitec",           name: "Capitec Bank",                logo: "capitec" },
  { id: "discovery_bank",    name: "Discovery Bank",              logo: "discovery_bank" },
  { id: "investec",          name: "Investec",                    logo: "investec" },
  { id: "african_bank",      name: "African Bank",                logo: "african_bank" },
  { id: "tyme_bank",         name: "TymeBank",                    logo: "tyme_bank" },
  { id: "bank_zero",         name: "Bank Zero",                   logo: "bank_zero" },
  { id: "old_mutual_bank",   name: "Old Mutual Bank",             logo: "old_mutual_bank" },
  { id: "sasfin",            name: "Sasfin Bank",                 logo: "sasfin" }
].freeze
