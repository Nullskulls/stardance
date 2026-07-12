module ExternalDashboard
  class CertReturnJob < WebhookJob
    def perform(cert_id, backfill_run_id: nil)
      cert = Certification::Ship.find(cert_id)
      begin
        result = ExternalDashboard::CertReturnService.call(cert)
      rescue Faraday::Error => e
        record_sync(cert, :retrying, "return connection error: #{e.class}", backfill_run_id)
        raise
      end

      case result.status
      when :ok
        record_sync(cert, :ok, nil, backfill_run_id)
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} returned external_cert_id=#{cert.external_certification_id}"
      when :not_configured, :skipped
        record_sync(cert, :skipped, "return skipped: #{result.error}", backfill_run_id)
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} skipped (#{result.error})"
      when :client_error
        if result.error.to_s.match?(/only approved/i)
          record_sync(cert, :duplicate, nil, backfill_run_id)
          Rails.logger.info "[#{self.class.name}] cert=#{cert_id} already returned remotely (#{result.error})"
        else
          record_sync(cert, :failed, "return failed, http #{result.http_status}: #{result.error.presence || 'client error'}", backfill_run_id)
          log_remote_failure("client error", cert_id, result)
        end
      when :server_error
        record_sync(cert, :retrying, "return retrying, http #{result.http_status}: #{result.error.presence || 'server error'}", backfill_run_id)
        raise_server_error(cert_id, result)
      end
    end

    def record_terminal_failure(cert_id, message, run_id)
      cert = Certification::Ship.find_by(id: cert_id)
      record_sync(cert, :failed, "return gave up after retries: #{message}", run_id) if cert
    end
  end
end
