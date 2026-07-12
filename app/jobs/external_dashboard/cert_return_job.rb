module ExternalDashboard
  class CertReturnJob < WebhookJob
    def perform(cert_id, backfill_run_id: nil)
      cert = Certification::Ship.find(cert_id)
      begin
        result = ExternalDashboard::CertReturnService.call(cert)
      rescue Faraday::Error => e
        cert.record_external_sync!(error: "return connection error: #{e.class} (retrying)")
        raise
      end

      case result.status
      when :ok
        cert.record_external_sync!
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} returned external_cert_id=#{cert.external_certification_id}"
      when :not_configured, :skipped
        BackfillRun.record(backfill_run_id, :skipped)
        cert.record_external_sync!(error: "return skipped: #{result.error}")
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} skipped (#{result.error})"
      when :client_error
        if result.error.to_s.match?(/only approved/i)
          BackfillRun.record(backfill_run_id, :duplicate)
          cert.record_external_sync!
          Rails.logger.info "[#{self.class.name}] cert=#{cert_id} already returned remotely (#{result.error})"
        else
          BackfillRun.record(backfill_run_id, :failed)
          cert.record_external_sync!(error: "return failed — http #{result.http_status}: #{result.error.presence || 'client error'}")
          log_remote_failure("client error", cert_id, result)
        end
      when :server_error
        cert.record_external_sync!(error: "return retrying — http #{result.http_status}: #{result.error.presence || 'server error'}")
        raise_server_error(cert_id, result)
      end
    end

    def record_terminal_failure(cert_id, message)
      Certification::Ship.find_by(id: cert_id)&.record_external_sync!(error: "return gave up after retries: #{message}")
    end
  end
end
