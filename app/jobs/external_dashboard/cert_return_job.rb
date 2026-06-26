module ExternalDashboard
  class CertReturnJob < WebhookJob
    def perform(cert_id, reason)
      cert = Certification::Ship.find(cert_id)
      result = ExternalDashboard::CertReturnService.call(cert: cert, reason: reason)

      case result.status
      when :ok
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} returned external_cert_id=#{cert.external_certification_id}"
      when :not_configured, :skipped
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} skipped (#{result.error})"
      when :client_error
        log_remote_failure("client error", cert_id, result)
      when :server_error
        raise_server_error(cert_id, result)
      end
    end
  end
end
