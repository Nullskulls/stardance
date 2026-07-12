module ExternalDashboard
  class ShipWebhookJob < WebhookJob
    def perform(cert_id, backfill_run_id: nil, backfill: nil)
      cert = Certification::Ship.find(cert_id)
      fill_proof_video_url(cert)
      backfill = backfill_run_id.present? if backfill.nil?
      begin
        result = ExternalDashboard::ShipWebhookService.call(cert, backfill: backfill)
      rescue Faraday::Error => e
        record_sync(cert, :retrying, "connection error: #{e.class}", backfill_run_id)
        raise
      end

      case result.status
      when :ok, :duplicate
        saved = cert.assign_external_certification_id!(result.cert_id)
        record_ingest_outcome(cert, result, saved, backfill_run_id)
        chain_pending_return(cert, backfill_run_id)
        verb = result.status == :duplicate ? "already ingested" : "ingested"
        Rails.logger.info "[#{self.class.name}] cert=#{cert_id} #{verb} external_cert_id=#{result.cert_id}"
      when :not_configured, :skipped
        record_sync(cert, :skipped, result.error, backfill_run_id)
        level = cert.pending? ? :info : :warn
        Rails.logger.public_send(level, "[#{self.class.name}] cert=#{cert_id} skipped (#{result.error})")
      when :client_error
        record_sync(cert, :failed, "http #{result.http_status}: #{result.error.presence || 'client error'}", backfill_run_id)
        log_remote_failure("client error", cert_id, result)
      when :server_error
        record_sync(cert, :retrying, "http #{result.http_status}: #{result.error.presence || 'server error'}", backfill_run_id)
        raise_server_error(cert_id, result)
      end
    end

    def record_terminal_failure(cert_id, message, run_id)
      cert = Certification::Ship.find_by(id: cert_id)
      record_sync(cert, :failed, "gave up after retries: #{message}", run_id) if cert
    end

    private

      # Runs before chain_pending_return on purpose — the chain legitimately
      # blanks the uuid by transferring it to an active return, which must not
      # read as a failed save. A uuid already held by a sibling cert is the
      # same transfer seen from a later backfill, not an error.
      def record_ingest_outcome(cert, result, saved, run_id)
        return record_sync(cert, result.status, nil, run_id) unless saved == :skipped && cert.external_certification_id.blank?

        if result.cert_id.blank?
          record_sync(cert, :failed, "dashboard response carried no certId, uuid unknown", run_id)
          Rails.logger.warn "[#{self.class.name}] cert=#{cert.id} #{result.http_status} response without certId"
          return
        end
        unless result.cert_id.to_s.match?(Certification::Ship::EXTERNAL_CERTIFICATION_ID_PATTERN)
          record_sync(cert, :failed, "dashboard returned malformed certId (#{result.cert_id.to_s.truncate(60)})", run_id)
          Rails.logger.warn "[#{self.class.name}] cert=#{cert.id} malformed certId #{result.cert_id.inspect}"
          return
        end

        holder = Certification::Ship.where.not(id: cert.id).find_by(external_certification_id: result.cert_id.to_s)
        if holder
          message = "dashboard uuid held by cert ##{holder.id}"
          cert.record_external_sync!(error: message)
          record_event(cert, :duplicate, message, run_id)
          Rails.logger.info "[#{self.class.name}] cert=#{cert.id} uuid #{result.cert_id} already held by cert=#{holder.id}"
        else
          record_sync(cert, :failed, "ingested but uuid save failed (#{result.cert_id.inspect})", run_id)
          Rails.logger.warn "[#{self.class.name}] cert=#{cert.id} uuid save failed for #{result.cert_id.inspect}"
        end
      end

      def fill_proof_video_url(cert)
        return unless cert.proof_video_url.blank? && cert.verdict_video.attached?

        url_options = Rails.application.config.action_controller.default_url_options || {}
        return if url_options[:host].blank?

        url = Rails.application.routes.url_helpers.rails_blob_url(cert.verdict_video, **url_options)
        cert.update!(proof_video_url: url)
      rescue StandardError => e
        Rails.logger.warn "[#{self.class.name}] cert=#{cert.id} proof_video_url fill failed: #{e.class}: #{e.message}"
      end

      def chain_pending_return(cert, backfill_run_id)
        return unless cert.approved? && cert.external_certification_id.present?
        return if cert.post_ship_event_id.nil?

        project = cert.project
        return unless project

        active_return = project.ship_reviews.pending.where.not(returned_by_id: nil)
                               .find_by(post_ship_event_id: cert.post_ship_event_id)
        return unless active_return

        Certification::Ship.transaction do
          if cert.transfer_external_certification_id_to!(active_return)
            BackfillRun.record_enqueued(backfill_run_id)
            ExternalDashboard::CertReturnJob.perform_later(active_return.id, backfill_run_id: backfill_run_id)
          end
        end
      end
  end
end
