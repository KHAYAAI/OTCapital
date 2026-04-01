require "test_helper"

class StitchAccountTest < ActiveSupport::TestCase
  setup do
    @item = stitch_items(:one)
    @account = stitch_accounts(:one)
  end

  test "fixture is valid" do
    assert @account.valid?
  end

  test "belongs to stitch_item" do
    assert_equal @item, @account.stitch_item
  end

  test "requires remote_id" do
    @account.remote_id = nil
    assert_not @account.valid?
  end

  test "remote_id must be unique" do
    duplicate = StitchAccount.new(
      stitch_item: @item,
      remote_id: @account.remote_id,
      currency: "ZAR"
    )
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:remote_id], "has already been taken"
  end

  test "same remote_id can appear under a different stitch_item" do
    other_item = StitchItem.create!(family: families(:dylan_family), name: "Other")

    assert_difference "StitchAccount.count", 1 do
      StitchAccount.create!(
        stitch_item: other_item,
        remote_id: "unique-across-item-#{SecureRandom.hex(4)}",
        currency: "ZAR"
      )
    end
  end

  test "requires currency" do
    @account.currency = nil
    assert_not @account.valid?
  end

  test "upsert_stitch_snapshot! updates bank details from payload" do
    payload = {
      "bankId"        => "absa",
      "bankName"      => "ABSA Bank",
      "accountType"   => "cheque",
      "accountNumber" => "12345678",
      "currency"      => "ZAR"
    }

    @account.upsert_stitch_snapshot!(payload)
    @account.reload

    assert_equal "absa",          @account.bank_id
    assert_equal "ABSA Bank",     @account.bank_name
    assert_equal "cheque",        @account.account_type
    assert_equal "•••• 5678",     @account.account_number_masked
    assert_equal "ZAR",           @account.currency
  end

  test "upsert_stitch_snapshot! falls back to ZAR for blank currency" do
    payload = {
      "bankId" => "fnb", "bankName" => "FNB",
      "accountType" => "cheque", "accountNumber" => "0000",
      "currency" => nil
    }

    @account.upsert_stitch_snapshot!(payload)
    assert_equal "ZAR", @account.currency
  end

  test "SA_ACCOUNT_TYPE_MAP covers all expected Stitch types" do
    expected_types = %w[cheque savings creditCard loan]
    expected_types.each do |type|
      assert StitchAccount::SA_ACCOUNT_TYPE_MAP.key?(type),
             "Expected SA_ACCOUNT_TYPE_MAP to include '#{type}'"
    end
  end
end
