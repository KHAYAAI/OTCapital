require "test_helper"

class Provider::StitchAdapterTest < ActiveSupport::TestCase
  test "supports Depository accounts" do
    assert_includes Provider::StitchAdapter.supported_account_types, "Depository"
  end

  test "supports CreditCard accounts" do
    assert_includes Provider::StitchAdapter.supported_account_types, "CreditCard"
  end

  test "supports Loan accounts" do
    assert_includes Provider::StitchAdapter.supported_account_types, "Loan"
  end

  test "does not support Investment accounts" do
    assert_not_includes Provider::StitchAdapter.supported_account_types, "Investment"
  end

  test "connection_configs returns empty when family cannot connect stitch" do
    family = families(:dylan_family)
    family.stubs(:can_connect_stitch?).returns(false)

    configs = Provider::StitchAdapter.connection_configs(family: family)
    assert_empty configs
  end

  test "connection_configs returns stitch entry when family can connect" do
    family = families(:dylan_family)
    family.stubs(:can_connect_stitch?).returns(true)

    configs = Provider::StitchAdapter.connection_configs(family: family)
    assert_equal 1, configs.length
    assert_equal "stitch", configs.first[:key]
  end

  test "provider_name returns stitch" do
    adapter = Provider::StitchAdapter.new(stitch_accounts(:one))
    assert_equal "stitch", adapter.provider_name
  end

  test "institution_name returns bank_name from provider account" do
    sa = stitch_accounts(:one)
    adapter = Provider::StitchAdapter.new(sa)
    assert_equal sa.bank_name, adapter.institution_name
  end

  test "StitchAccount is registered in Provider::Factory" do
    adapter_class = Provider::Factory.adapter_for("StitchAccount")
    assert_equal Provider::StitchAdapter, adapter_class
  end
end
