module ExternalDashboard
  class ShipWebhookJob < WebhookJob
    def perform(cert_id)
      cert = Certification::Ship.find(cert_id)
      result = ExternalDashboard::ShipWebhookService.call(cert)

      case result.status
      when :ok
        cert.assign_external_certification_id!(result.cert_id)
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} ingested external_cert_id=#{result.cert_id}"
      when :duplicate
        cert.assign_external_certification_id!(result.cert_id)
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} already ingested external_cert_id=#{result.cert_id}"
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
