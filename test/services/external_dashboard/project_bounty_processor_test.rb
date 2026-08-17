require "test_helper"

class ExternalDashboard::ProjectBountyProcessorTest < ActiveSupport::TestCase
  include UserFactory

  setup do
    @owner = create_user(slack_id: "U_BOUNTY_OWNER", display_name: "bountyowner")
    @setter = create_user(slack_id: "U_BOUNTY_SETTER", display_name: "bountysetter")
    @project = Project.create!(title: "Bountied Ship", description: "A ship", ship_status: "submitted")
    @project.memberships.create!(user: @owner, role: :owner)
    @cert = Certification::Ship.create!(
      project: @project,
      status: :pending,
      external_certification_id: "11111111-1111-1111-1111-111111111111"
    )
  end

  test "responds to a test connection without touching the project" do
    result = ExternalDashboard::ProjectBountyProcessor.call(certification: { id: "test" }, amount: "500")

    assert_equal :ok, result.status
    assert result.body[:test]
    assert_nil @project.reload.bounty_stardust
  end

  test "rejects a payload missing the certification object" do
    result = ExternalDashboard::ProjectBountyProcessor.call(amount: "500")

    assert_equal :bad_request, result.status
    assert_match(/missing certification/, result.body[:error])
  end

  test "rejects a non-integer amount" do
    result = ExternalDashboard::ProjectBountyProcessor.call(
      certification: { id: @cert.external_certification_id },
      amount: "not-a-number"
    )

    assert_equal :bad_request, result.status
    assert_match(/invalid amount/, result.body[:error])
  end

  test "returns not_found when the cert can't be resolved" do
    result = ExternalDashboard::ProjectBountyProcessor.call(
      certification: { id: "99999999-9999-9999-9999-999999999999" },
      amount: "500"
    )

    assert_equal :not_found, result.status
  end

  test "refuses to set a bounty once the review is decided" do
    @cert.update!(status: :approved)

    result = ExternalDashboard::ProjectBountyProcessor.call(
      certification: { id: @cert.external_certification_id },
      amount: "500"
    )

    assert_equal :conflict, result.status
    assert_nil @project.reload.bounty_stardust
  end

  test "sets the bounty by external_certification_id and returns it" do
    result = ExternalDashboard::ProjectBountyProcessor.call(
      certification: { id: @cert.external_certification_id },
      amount: "750",
      setBy: @setter.slack_id
    )

    assert_equal :ok, result.status
    assert_equal 750, @project.reload.bounty_stardust
    assert_equal 750, result.body[:bountyStardust]
    assert_equal @project.id, result.body[:projectId]
  end

  test "sets the bounty by the legacy externalId when no uuid matches" do
    result = ExternalDashboard::ProjectBountyProcessor.call(
      certification: { id: "not-a-uuid", externalId: @cert.id.to_s },
      amount: "100"
    )

    assert_equal :ok, result.status
    assert_equal 100, @project.reload.bounty_stardust
  end

  test "attributes the paper trail version to the resolved setter" do
    ExternalDashboard::ProjectBountyProcessor.call(
      certification: { id: @cert.external_certification_id },
      amount: "250",
      setBy: @setter.slack_id
    )

    version = PaperTrail::Version.find_by(item_type: "Project", item_id: @project.id, event: "update")
    assert_equal @setter.id.to_s, version.whodunnit
  end
end
