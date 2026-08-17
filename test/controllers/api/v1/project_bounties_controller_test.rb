require "test_helper"

class Api::V1::ProjectBountiesControllerTest < ActionDispatch::IntegrationTest
  include UserFactory

  API_KEY = "test-api-key".freeze
  WORKPLACE_ID = "test-workplace-id".freeze

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

  test "rejects requests with no api key" do
    ExternalDashboard::Client.stub(:api_key, API_KEY) do
      ExternalDashboard::Client.stub(:workplace_id, WORKPLACE_ID) do
        post api_v1_project_bounties_path,
          params: { certification: { id: @cert.external_certification_id }, amount: "500" }.to_json,
          headers: { "Content-Type" => "application/json" }
      end
    end

    assert_response :unauthorized
  end

  test "rejects requests with the wrong workplace id" do
    ExternalDashboard::Client.stub(:api_key, API_KEY) do
      ExternalDashboard::Client.stub(:workplace_id, WORKPLACE_ID) do
        post api_v1_project_bounties_path,
          params: { certification: { id: @cert.external_certification_id }, amount: "500" }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "x-api-key" => API_KEY,
            "x-workplace-id" => "wrong"
          }
      end
    end

    assert_response :unauthorized
  end

  test "sets the bounty when authenticated" do
    ExternalDashboard::Client.stub(:api_key, API_KEY) do
      ExternalDashboard::Client.stub(:workplace_id, WORKPLACE_ID) do
        post api_v1_project_bounties_path,
          params: { certification: { id: @cert.external_certification_id }, amount: "500" }.to_json,
          headers: {
            "Content-Type" => "application/json",
            "x-api-key" => API_KEY,
            "x-workplace-id" => WORKPLACE_ID
          }
      end
    end

    assert_response :success
    assert_equal 500, @project.reload.bounty_stardust
    assert_equal 500, JSON.parse(response.body)["bountyStardust"]
  end

  test "returns bad_request for malformed json" do
    ExternalDashboard::Client.stub(:api_key, API_KEY) do
      ExternalDashboard::Client.stub(:workplace_id, WORKPLACE_ID) do
        post api_v1_project_bounties_path,
          params: "not json",
          headers: {
            "Content-Type" => "application/json",
            "x-api-key" => API_KEY,
            "x-workplace-id" => WORKPLACE_ID
          }
      end
    end

    assert_response :bad_request
  end
end
