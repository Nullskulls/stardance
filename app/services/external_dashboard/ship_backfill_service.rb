module ExternalDashboard
  class ShipBackfillService
    BATCH_SIZE = 100

    Result = Struct.new(:status, :enqueued, :error, keyword_init: true) do
      def ok? = status == :ok
    end

    def self.call(scope: nil)
      return Result.new(status: :not_configured, enqueued: 0, error: "api key or workplace id missing") unless Client.configured?

      scope ||= Post::ShipEvent.where(external_certification_id: nil)
      enqueued = 0
      scope.find_each(batch_size: BATCH_SIZE) do |ship_event|
        ExternalDashboard::ShipWebhookJob.perform_later(ship_event.id)
        enqueued += 1
      end

      Rails.logger.info "[ExternalDashboard::ShipBackfillService] enqueued=#{enqueued}"
      Result.new(status: :ok, enqueued: enqueued)
    end
  end
end
