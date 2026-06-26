module ExternalDashboard
  class ShipWebhookJob < ApplicationJob
    queue_as :default

    discard_on ActiveRecord::RecordNotFound

    retry_on Faraday::Error, wait: 30.seconds, attempts: 2 do |job, error|
      Rails.logger.warn "[ExternalDashboard::ShipWebhookJob] ship_event=#{job.arguments.first} giving up after Faraday error: #{error.class}: #{error.message}"
      Sentry.capture_message(
        "ExternalDashboard ship webhook gave up after network errors",
        level: :warning,
        extra: { ship_event_id: job.arguments.first, error_class: error.class.name, error_message: error.message.to_s.truncate(ExternalDashboard::ShipWebhookService::ERROR_MESSAGE_MAX) }
      )
    end

    def perform(ship_event_id)
      ship_event = Post::ShipEvent.find(ship_event_id)
      result = ExternalDashboard::ShipWebhookService.call(ship_event)

      case result.status
      when :ok
        persist_cert_id(ship_event, result.cert_id)
        Rails.logger.info "[ExternalDashboard::ShipWebhookJob] ship_event=#{ship_event_id} ingested cert_id=#{result.cert_id}"
      when :duplicate
        persist_cert_id(ship_event, result.cert_id)
        Rails.logger.info "[ExternalDashboard::ShipWebhookJob] ship_event=#{ship_event_id} already ingested cert_id=#{result.cert_id}"
      when :not_configured, :skipped
        Rails.logger.info "[ExternalDashboard::ShipWebhookJob] ship_event=#{ship_event_id} skipped (#{result.error})"
      when :client_error
        log_remote_failure(ship_event_id, result, "client error")
      when :server_error
        log_remote_failure(ship_event_id, result, "server error")
      end
    end

    private

    def persist_cert_id(ship_event, cert_id)
      ship_event.assign_external_certification_id!(cert_id)
    end

    def log_remote_failure(ship_event_id, result, label)
      Rails.logger.warn "[ExternalDashboard::ShipWebhookJob] ship_event=#{ship_event_id} #{label} http=#{result.http_status} error=#{result.error}"
      Sentry.capture_message(
        "ExternalDashboard ship webhook #{label}",
        level: :warning,
        extra: { ship_event_id: ship_event_id, http_status: result.http_status, error: result.error }
      )
    end
  end
end
