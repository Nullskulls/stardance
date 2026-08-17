require "test_helper"

class ProjectBountyTest < ActiveSupport::TestCase
  include UserFactory

  setup do
    @owner = create_user(slack_id: "U_PROJBOUNTY_OWNER", display_name: "projbountyowner")
    @reviewer = create_user(slack_id: "U_PROJBOUNTY_REV", display_name: "projbountyreviewer")
    @project = Project.create!(title: "Bounty Test Ship", description: "A ship", ship_status: "submitted")
    @project.memberships.create!(user: @owner, role: :owner)
  end

  test "grant_bounty! does nothing when no bounty is set" do
    assert_no_difference -> { @owner.reload.ledger_entries.count } do
      @project.grant_bounty!
    end
  end

  test "grant_bounty! does nothing for a zero or negative bounty" do
    @project.update_column(:bounty_stardust, 0)

    assert_no_difference -> { @owner.reload.ledger_entries.count } do
      @project.grant_bounty!
    end
  end

  test "grant_bounty! grants stardust to the project owner and stamps bounty_paid_at" do
    @project.update!(bounty_stardust: 300)

    assert_difference -> { @owner.reload.ledger_entries.count }, 1 do
      @project.grant_bounty!
    end

    entry = @owner.ledger_entries.last
    assert_equal 300, entry.amount
    assert_equal @project, entry.ledgerable
    assert @project.reload.bounty_paid_at.present?
  end

  test "grant_bounty! is idempotent once paid" do
    @project.update!(bounty_stardust: 300)
    @project.grant_bounty!

    assert_no_difference -> { @owner.reload.ledger_entries.count } do
      @project.grant_bounty!
    end
  end

  test "approving the ship review pays out the project's bounty" do
    @project.update!(bounty_stardust: 150)

    assert_difference -> { @owner.reload.ledger_entries.count }, 1 do
      @project.ship_reviews.create!(status: :approved, reviewer: @reviewer)
    end

    assert @project.reload.bounty_paid_at.present?
    assert_equal "approved", @project.ship_status
  end

  test "returning the ship review does not pay out a bounty" do
    @project.update!(bounty_stardust: 150)

    assert_no_difference -> { @owner.reload.ledger_entries.count } do
      @project.ship_reviews.create!(status: :returned, reviewer: @reviewer)
    end

    assert_nil @project.reload.bounty_paid_at
  end
end
