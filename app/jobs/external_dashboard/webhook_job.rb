module ExternalDashboard
  class WebhookJob < ::ApplicationJob
    queue_as :default

    self.enqueue_after_transaction_commit = true

    discard_on ActiveRecord::RecordNotFound

    retry_on Faraday::Error, wait: 30.seconds, attempts: 2 do |job, error|
      ship_event_id = job.arguments.first
      Rails.logger.warn "[#{job.class.name}] ship_event=#{ship_event_id} giving up after Faraday error: #{error.class}: #{error.message}"
      Sentry.capture_message(
        "ExternalDashboard webhook gave up after network errors",
        level: :warning,
        extra: {
          job_class: job.class.name,
          ship_event_id: ship_event_id,
          error_class: error.class.name,
          error_message: error.message.to_s.truncate(ExternalDashboard::Client::ERROR_MESSAGE_MAX)
        }
      )
    end

    private

      def log_remote_failure(label, ship_event_id, result)
        Rails.logger.warn "[#{self.class.name}] ship_event=#{ship_event_id} #{label} http=#{result.http_status} error=#{result.error}"
        Sentry.capture_message(
          "ExternalDashboard webhook #{label}",
          level: :warning,
          extra: {
            job_class: self.class.name,
            ship_event_id: ship_event_id,
            http_status: result.http_status,
            error: result.error
          }
        )
      end
  end
end
