require "test_helper"

class CleanupGuestUsersJobTest < ActiveJob::TestCase
  test "destroys guests older than 30 days" do
    old_guest = User.create!(email: "old-guest@example.test", display_name: "Old Guest")
    old_guest.update_columns(created_at: 31.days.ago)

    assert_difference "User.count", -1 do
      CleanupGuestUsersJob.new.perform
    end

    refute User.exists?(old_guest.id)
  end

  test "leaves guests within the retention window" do
    fresh_guest = User.create!(email: "fresh-guest@example.test", display_name: "Fresh Guest")
    fresh_guest.update_columns(created_at: 5.days.ago)

    assert_no_difference "User.count" do
      CleanupGuestUsersJob.new.perform
    end
  end

  test "aborts and warns when found exceeds MAX_PER_RUN" do
    original = CleanupGuestUsersJob::MAX_PER_RUN
    CleanupGuestUsersJob.send(:remove_const, :MAX_PER_RUN)
    CleanupGuestUsersJob.const_set(:MAX_PER_RUN, 1)

    2.times do |i|
      u = User.create!(email: "over-cap-#{i}@example.test", display_name: "Over #{i}")
      u.update_columns(created_at: 31.days.ago)
    end

    assert_no_difference "User.count" do
      CleanupGuestUsersJob.new.perform
    end
  ensure
    CleanupGuestUsersJob.send(:remove_const, :MAX_PER_RUN)
    CleanupGuestUsersJob.const_set(:MAX_PER_RUN, original) if original
  end

  test "leaves HCA-linked users regardless of age" do
    old_hca_user = User.create!(
      email: "old-hca@example.test",
      display_name: "Old HCA",
      slack_id: "U_OLD_HCA"
    )
    old_hca_user.identities.create!(
      provider: "hack_club",
      uid: "hca-old",
      access_token: "fake-token"
    )
    old_hca_user.update_columns(created_at: 365.days.ago)

    assert_no_difference "User.count" do
      CleanupGuestUsersJob.new.perform
    end

    assert User.exists?(old_hca_user.id)
  end
end
