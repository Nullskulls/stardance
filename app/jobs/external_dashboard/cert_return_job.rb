module ExternalDashboard
  class CertReturnJob < ApplicationJob
    queue_as :default

    self.enqueue_after_transaction_commit = true

    discard_on ActiveRecord::RecordNotFound

    retry_on Faraday::Error, wait: 30.seconds, attempts: 2 do |job, error|
      ship_event_id, * = job.arguments
      Rails.logger.warn "[ExternalDashboard::CertReturnJob] ship_event=#{ship_event_id} giving up after Faraday error: #{error.class}: #{error.message}"
      Sentry.capture_message(
        "ExternalDashboard cert return gave up after network errors",
        level: :warning,
        extra: { ship_event_id: ship_event_id, error_class: error.class.name, error_message: error.message.to_s.truncate(ExternalDashboard::CertReturnService::ERROR_MESSAGE_MAX) }
      )
    end

    def perform(ship_event_id, reason)
      ship_event = Post::ShipEvent.find(ship_event_id)
      result = ExternalDashboard::CertReturnService.call(ship_event: ship_event, reason: reason)

      case result.status
      when :ok
        Rails.logger.info "[ExternalDashboard::CertReturnJob] ship_event=#{ship_event_id} returned cert=#{ship_event.external_certification_id}"
      when :not_configured, :skipped
        Rails.logger.info "[ExternalDashboard::CertReturnJob] ship_event=#{ship_event_id} skipped (#{result.error})"
      when :client_error
        log_remote_failure(ship_event_id, result, "client error")
      when :server_error
        log_remote_failure(ship_event_id, result, "server error")
      end
    end

    private

    def log_remote_failure(ship_event_id, result, label)
      Rails.logger.warn "[ExternalDashboard::CertReturnJob] ship_event=#{ship_event_id} #{label} http=#{result.http_status} error=#{result.error}"
      Sentry.capture_message(
        "ExternalDashboard cert return #{label}",
        level: :warning,
        extra: { ship_event_id: ship_event_id, http_status: result.http_status, error: result.error }
      )
    end
  end
end
