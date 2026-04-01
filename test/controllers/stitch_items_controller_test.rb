require "test_helper"
require "ostruct"

class StitchItemsControllerTest < ActionDispatch::IntegrationTest
  setup do
    sign_in @user = users(:family_admin)
    @family = @user.family
    @item = stitch_items(:one)
  end

  # ---------------------------------------------------------------------------
  # GET new
  # ---------------------------------------------------------------------------
  test "new renders the connection form" do
    get new_stitch_item_url
    assert_response :success
  end

  # ---------------------------------------------------------------------------
  # POST create — redirects to Stitch link URL
  # ---------------------------------------------------------------------------
  test "create builds a stitch item and redirects to stitch link URL" do
    stitch = mock("Provider::Stitch")
    StitchItem.any_instance.stubs(:stitch_provider).returns(stitch)

    link_url = "https://secure.stitch.money/connect?token=abc"
    stitch.expects(:create_link_token).returns(
      OpenStruct.new(link_url: link_url, nonce: "nonce_abc")
    )

    assert_difference "StitchItem.count", 1 do
      post stitch_items_url, params: { stitch_item: { name: "My FNB" } }
    end

    assert_redirected_to link_url
  end

  test "create renders new with error when name blank" do
    post stitch_items_url, params: { stitch_item: { name: "" } }
    assert_response :unprocessable_entity
  end

  # ---------------------------------------------------------------------------
  # GET callback — stores user_interaction_id in session
  # ---------------------------------------------------------------------------
  test "callback stores user_interaction_id and redirects to setup_accounts" do
    get callback_stitch_items_url, params: {
      id: @item.id,
      user_interaction_id: "ui_abc123"
    }

    assert_redirected_to setup_accounts_stitch_item_url(@item)
  end

  test "callback redirects to providers with alert when id missing" do
    get callback_stitch_items_url, params: { user_interaction_id: "ui_abc123" }
    assert_redirected_to settings_providers_path
  end

  # ---------------------------------------------------------------------------
  # POST sync
  # ---------------------------------------------------------------------------
  test "sync queues background sync job" do
    StitchItem.any_instance.expects(:sync_later).once
    post sync_stitch_item_url(@item)
    assert_redirected_to accounts_path
  end

  # ---------------------------------------------------------------------------
  # DELETE destroy — soft-delete
  # ---------------------------------------------------------------------------
  test "destroy schedules item for deletion" do
    StitchItem.any_instance.expects(:destroy_later).once
    delete stitch_item_url(@item)

    assert_redirected_to settings_providers_path
    assert_match(/scheduled for deletion/i, flash[:notice])
  end

  # ---------------------------------------------------------------------------
  # PATCH update — rename connection
  # ---------------------------------------------------------------------------
  test "update renames the stitch item" do
    patch stitch_item_url(@item), params: { stitch_item: { name: "Renamed FNB" } }
    assert_equal "Renamed FNB", @item.reload.name
    assert_redirected_to settings_providers_path
  end

  # ---------------------------------------------------------------------------
  # Authentication guard
  # ---------------------------------------------------------------------------
  test "all actions require authentication" do
    sign_out

    get new_stitch_item_url
    assert_redirected_to new_session_path

    post stitch_items_url, params: { stitch_item: { name: "X" } }
    assert_redirected_to new_session_path
  end
end
