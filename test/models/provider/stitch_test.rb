require "test_helper"

class Provider::StitchTest < ActiveSupport::TestCase
  setup do
    @provider = Provider::Stitch.new(
      client_id: "test_client_id",
      client_secret: "test_client_secret"
    )
  end

  # ---------------------------------------------------------------------------
  # Initialisation
  # ---------------------------------------------------------------------------
  test "initializes with client_id and client_secret" do
    assert_equal "test_client_id", @provider.client_id
    assert_equal "test_client_secret", @provider.client_secret
  end

  # ---------------------------------------------------------------------------
  # StitchError
  # ---------------------------------------------------------------------------
  test "StitchError stores a reason symbol" do
    err = Provider::Stitch::StitchError.new("something went wrong", reason: :unauthorized)
    assert_equal :unauthorized, err.reason
    assert_equal "something went wrong", err.message
  end

  test "StitchError defaults reason to nil" do
    err = Provider::Stitch::StitchError.new("oops")
    assert_nil err.reason
  end

  # ---------------------------------------------------------------------------
  # SA_BANKS constant
  # ---------------------------------------------------------------------------
  test "SA_BANKS is defined and frozen" do
    assert_kind_of Array, SA_BANKS
    assert SA_BANKS.frozen?
  end

  test "SA_BANKS contains the 12 major SA banks" do
    ids = SA_BANKS.map { |b| b[:id] }
    %w[fnb standard_bank absa nedbank capitec discovery_bank investec].each do |id|
      assert_includes ids, id, "SA_BANKS missing #{id}"
    end
  end

  test "each SA bank entry has id, name, and logo keys" do
    SA_BANKS.each do |bank|
      assert bank[:id].present?,   "Bank entry missing :id"
      assert bank[:name].present?, "Bank entry missing :name"
      assert bank[:logo].present?, "Bank entry missing :logo"
    end
  end

  # ---------------------------------------------------------------------------
  # Market mode helpers (Family concern)
  # ---------------------------------------------------------------------------
  test "family sa_market? returns true for SA market mode" do
    family = families(:dylan_family)
    family.market_mode = "sa"
    assert family.sa_market?
    assert_not family.global_market?
  end

  test "family global_market? returns true for global market mode" do
    family = families(:dylan_family)
    family.market_mode = "global"
    assert family.global_market?
    assert_not family.sa_market?
  end

  test "family market_mode validates against known modes" do
    family = families(:dylan_family)
    family.market_mode = "invalid"
    assert_not family.valid?
    assert_includes family.errors[:market_mode], "is not included in the list"
  end
end
