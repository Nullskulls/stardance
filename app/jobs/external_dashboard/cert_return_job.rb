module ExternalDashboard
  class CertReturnJob < WebhookJob
    def perform(ship_event_id, reason)
      ship_event = Post::ShipEvent.find(ship_event_id)
      result = ExternalDashboard::CertReturnService.call(ship_event: ship_event, reason: reason)

      case result.status
      when :ok
        Rails.logger.info "[#{self.class.name}] ship_event=#{ship_event_id} returned cert=#{ship_event.external_certification_id}"
      when :not_configured, :skipped
        Rails.logger.info "[#{self.class.name}] ship_event=#{ship_event_id} skipped (#{result.error})"
      when :client_error
        log_remote_failure("client error", ship_event_id, result)
      when :server_error
        raise_server_error(ship_event_id, result)
      end
    end
  end
end
