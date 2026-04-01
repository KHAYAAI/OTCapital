require "test_helper"

class StitchItemTest < ActiveSupport::TestCase
  setup do
    @item = stitch_items(:one)
    @family = families(:dylan_family)
  end

  test "fixture is valid" do
    assert @item.valid?
  end

  test "belongs to family" do
    assert_equal @family, @item.family
  end

  test "requires name" do
    @item.name = nil
    assert_not @item.valid?
    assert_includes @item.errors[:name], "can't be blank"
  end

  test "status defaults to good" do
    item = StitchItem.new(family: @family, name: "New")
    assert item.good?
  end

  test "requires_update scope returns only items needing re-auth" do
    assert_includes StitchItem.needs_update, stitch_items(:requires_update)
    assert_not_includes StitchItem.needs_update, @item
  end

  test "active scope excludes items scheduled for deletion" do
    @item.update!(scheduled_for_deletion: true)
    assert_not_includes StitchItem.active, @item
  end

  test "active scope includes items not scheduled for deletion" do
    assert_includes StitchItem.active, @item
  end

  test "token_valid? returns false when token_id is blank" do
    @item.token_id = nil
    assert_not @item.token_valid?
  end

  test "token_valid? returns true when token_id present and no expiry" do
    @item.token_id = "tok_abc123"
    @item.token_expires_at = nil
    assert @item.token_valid?
  end

  test "token_valid? returns false when token has expired" do
    @item.token_id = "tok_abc123"
    @item.token_expires_at = 1.hour.ago
    assert_not @item.token_valid?
  end

  test "token_valid? returns true when token has not yet expired" do
    @item.token_id = "tok_abc123"
    @item.token_expires_at = 1.hour.from_now
    assert @item.token_valid?
  end

  test "display_name returns name when present" do
    @item.name = "My FNB"
    assert_equal "My FNB", @item.display_name
  end

  test "display_name returns fallback when name blank" do
    @item.name = ""
    assert_equal "Stitch Connection", @item.display_name
  end

  test "destroy_later sets scheduled_for_deletion flag and queues DestroyJob" do
    assert_enqueued_with(job: DestroyJob) do
      @item.destroy_later
    end
    assert @item.reload.scheduled_for_deletion
  end

  test "has many stitch_accounts" do
    assert_respond_to @item, :stitch_accounts
  end

  test "has many accounts through stitch_accounts" do
    assert_respond_to @item, :accounts
  end
end
