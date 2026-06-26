module ExternalDashboard
  class ShipWebhookJob < WebhookJob
    def perform(ship_event_id)
      ship_event = Post::ShipEvent.find(ship_event_id)
      result = ExternalDashboard::ShipWebhookService.call(ship_event)

      case result.status
      when :ok
        ship_event.assign_external_certification_id!(result.cert_id)
        Rails.logger.info "[#{self.class.name}] ship_event=#{ship_event_id} ingested cert_id=#{result.cert_id}"
      when :duplicate
        ship_event.assign_external_certification_id!(result.cert_id)
        Rails.logger.info "[#{self.class.name}] ship_event=#{ship_event_id} already ingested cert_id=#{result.cert_id}"
      when :not_configured, :skipped
        Rails.logger.info "[#{self.class.name}] ship_event=#{ship_event_id} skipped (#{result.error})"
      when :client_error
        log_remote_failure("client error", ship_event_id, result)
      when :server_error
        log_remote_failure("server error", ship_event_id, result)
      end
    end
  end
end
