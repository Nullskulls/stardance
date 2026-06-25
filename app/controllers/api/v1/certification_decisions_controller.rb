class Api::V1::CertificationDecisionsController < Api::V1::BaseController
  def create
    result = ExternalDashboard::DecisionProcessor.call(request.request_parameters)
    render json: result.body, status: result.status
  end

  private

    def credential_api_keys
      Array.wrap(Rails.application.credentials.dig(:external_dashboard, :decision_api_keys)) +
        Array.wrap(ENV["EXTERNAL_REVIEW_API_KEY"])
    end
end
