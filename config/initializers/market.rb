# =============================================================================
# OTCapital — Market Mode Configuration
# =============================================================================
#
# PURPOSE
# -------
# OTCapital runs in two market modes:
#
#   "sa"     → South Africa (PRIMARY). ZAR currency, Stitch open-banking,
#               SA bank list, DD/MM/YYYY date format defaults.
#
#   "global" → US/EU mode (SECONDARY). Keeps all original Plaid, SimpleFIN,
#               Enable Banking and other US/EU providers working unchanged.
#               Useful for international users or white-label deployments.
#
# HOW IT WORKS
# ------------
# There are TWO layers of market mode:
#
#   1. App-level default  →  config.x.default_market_mode  (set by MARKET_MODE env)
#      Applied at registration time to every new Family created on this instance.
#
#   2. Family-level preference  →  families.market_mode  (stored per family)
#      Each family can switch independently via Settings → Preferences → Market.
#      This overrides the app default for that family everywhere.
#
# CHANGING THE DEFAULT FOR YOUR INSTANCE
# ---------------------------------------
#   MARKET_MODE=sa      (default — SA-first: ZAR, Stitch, SA banks)
#   MARKET_MODE=global  (US/EU-first: USD, Plaid, Enable Banking)
#
# WHERE MARKET MODE IS USED
# -------------------------
#   Family#sa_market?        → boolean helper used in views/controllers
#   Family#global_market?    → boolean helper
#   Family#can_connect_stitch? → gates Stitch provider availability
#   Settings::Providers view → shows Stitch panel first when sa_market?
#   RegistrationsController  → sets ZAR+ZA defaults for new SA families
#
# ADDING A NEW SA-SPECIFIC FEATURE
# ---------------------------------
#   Guard it with:  if Current.family.sa_market?
#   Guard it with:  unless Current.family.global_market?
#
# =============================================================================

Rails.application.configure do
  # Default market mode: "sa" for South Africa (primary), "global" for US/EU
  config.x.default_market_mode = ENV.fetch("MARKET_MODE", "sa")
end

# SA_BANKS — canonical list of South African banks supported by Stitch.
#
# The `id` field corresponds to the bankId values returned by the Stitch API.
# The `logo` field is a placeholder for future asset pipeline integration
# (e.g. app/assets/images/banks/<logo>.svg). Add new banks as Stitch expands
# their coverage — check https://stitch.money/docs for the current list.
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
