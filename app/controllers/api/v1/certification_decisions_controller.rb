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
      return reject_auth("secret not configured") if secret.blank?

      header = request.headers[SIGNATURE_HEADER].to_s.strip
      return reject_auth("missing signature header") if header.blank?
      return reject_auth("malformed signature header") unless header.start_with?(SIGNATURE_PREFIX)

      provided = header.delete_prefix(SIGNATURE_PREFIX).downcase
      expected = OpenSSL::HMAC.hexdigest("SHA256", secret, request.raw_post)

      return true if ActiveSupport::SecurityUtils.secure_compare(expected, provided)
      reject_auth("signature mismatch")
    end

    def webhook_secret
      raw = Rails.application.credentials.dig(:external_dashboard, :decision_webhook_secret).presence ||
            ENV["EXTERNAL_REVIEW_SECRET"].presence
      raw.is_a?(String) ? raw : nil
    end

    def reject_auth(reason)
      Rails.logger.warn "[CertificationDecisions] rejected: #{reason}"
      false
    end
end
