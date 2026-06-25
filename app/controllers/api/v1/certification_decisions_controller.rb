class Api::V1::CertificationDecisionsController < Api::V1::BaseController
  SIGNATURE_HEADER = "X-Shipwrights-Signature".freeze
  SIGNATURE_PREFIX = "sha256=".freeze

  def create
    result = ExternalDashboard::DecisionProcessor.call(request.request_parameters)
    render json: result.body, status: result.status
  end

  private

    def valid_api_key?
      secret = webhook_secret
      return false if secret.blank?

      header = request.headers[SIGNATURE_HEADER].to_s
      return false unless header.start_with?(SIGNATURE_PREFIX)

      provided = header.delete_prefix(SIGNATURE_PREFIX)
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)

      ActiveSupport::SecurityUtils.secure_compare(expected, provided)
    end

    def webhook_secret
      Rails.application.credentials.dig(:external_dashboard, :decision_webhook_secret).presence ||
        ENV["EXTERNAL_REVIEW_SECRET"].presence
    end
end
