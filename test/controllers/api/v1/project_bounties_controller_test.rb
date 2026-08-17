require "test_helper"

class Api::V1::ProjectBountiesControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  SECRET = "test-webhook-secret".freeze

  setup do
    @owner = create_user(slack_id: "U_BOUNTYAPI_OWNER", display_name: "bountyapiowner")
    @project = Project.create!(title: "Bountied via API", description: "A ship", ship_status: "submitted")
    @project.memberships.create!(user: @owner, role: :owner)
    @cert = Certification::Ship.create!(
      project: @project,
      status: :pending,
      external_certification_id: "22222222-2222-2222-2222-222222222222"
    )
  end

  test "rejects requests with no signature" do
    ExternalDashboard::Client.stub(:decision_webhook_secret, SECRET) do
      post api_v1_project_bounties_path,
        params: { certification: { id: @cert.external_certification_id }, amount: "500" }.to_json,
        headers: { "Content-Type" => "application/json" }
    end

    assert_response :unauthorized
  end

  test "rejects requests with a bad signature" do
    ExternalDashboard::Client.stub(:decision_webhook_secret, SECRET) do
      post api_v1_project_bounties_path,
        params: { certification: { id: @cert.external_certification_id }, amount: "500" }.to_json,
        headers: {
          "Content-Type" => "application/json",
          "X-Shipwrights-Signature" => "sha256=#{"0" * 64}"
        }
    end

    assert_response :unauthorized
  end

  test "sets the bounty when the signature is valid" do
    body = { certification: { id: @cert.external_certification_id }, amount: "500" }.to_json

    ExternalDashboard::Client.stub(:decision_webhook_secret, SECRET) do
      post api_v1_project_bounties_path,
        params: body,
        headers: {
          "Content-Type" => "application/json",
          "X-Shipwrights-Signature" => signature_for(body)
        }
    end

    assert_response :success
    assert_equal 500, @project.reload.bounty_stardust
    assert_equal 500, JSON.parse(response.body)["bountyStardust"]
  end

  test "returns bad_request for malformed json" do
    body = "not json"

    ExternalDashboard::Client.stub(:decision_webhook_secret, SECRET) do
      post api_v1_project_bounties_path,
        params: body,
        headers: {
          "Content-Type" => "application/json",
          "X-Shipwrights-Signature" => signature_for(body)
        }
    end

    assert_response :bad_request
  end

  private

    def signature_for(raw_body)
      "sha256=" + OpenSSL::HMAC.hexdigest("SHA256", SECRET, raw_body)
    end
end
