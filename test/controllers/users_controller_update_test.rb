require "test_helper"

class UsersControllerUpdateTest < ActionDispatch::IntegrationTest
  setup do
    @alice = create_user(slack_id: "U_ALICE", display_name: "alice")
    @bob   = create_user(slack_id: "U_BOB",   display_name: "bob")
  end

  test "owner can update their bio" do
    sign_in @alice
    patch user_path(@alice), params: { user: { bio: "hello world" } }
    assert_redirected_to user_path(@alice)
    assert_equal "hello world", @alice.reload.bio
  end

  test "owner can update with token-style bio" do
    sign_in @alice
    patch user_path(@alice), params: { user: { bio: "shout out to <@#{@bob.id}>" } }
    assert_equal "shout out to <@#{@bob.id}>", @alice.reload.bio
  end

  test "non-owner cannot update someone else's profile" do
    sign_in @bob
    patch user_path(@alice), params: { user: { bio: "hacked" } }
    assert_response :forbidden
    assert_not_equal "hacked", @alice.reload.bio
  end

  test "logged-out users cannot update" do
    patch user_path(@alice), params: { user: { bio: "hi" } }
    assert_response :forbidden
    assert_not_equal "hi", @alice.reload.bio
  end
end
