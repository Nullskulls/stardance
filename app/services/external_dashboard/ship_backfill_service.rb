module ExternalDashboard
  class ShipBackfillService
    BATCH_SIZE = 100
    DEFAULT_RATE_PER_SECOND = 2

    Result = Struct.new(:status, :enqueued, :error, keyword_init: true) do
      def ok? = status == :ok
    end

    def self.call(scope: nil, rate_per_second: DEFAULT_RATE_PER_SECOND)
      return Result.new(status: :not_configured, enqueued: 0, error: "api key or workplace id missing") unless Client.configured?

      scope ||= Certification::Ship.where(external_certification_id: nil)
      enqueued = 0
      scope.find_each(batch_size: BATCH_SIZE) do |cert|
        delay = (enqueued.to_f / rate_per_second).seconds
        ExternalDashboard::ShipWebhookJob.set(wait: delay).perform_later(cert.id)
        enqueued += 1
      end

      Rails.logger.info "[ExternalDashboard::ShipBackfillService] enqueued=#{enqueued} rate=#{rate_per_second}/s"
      Result.new(status: :ok, enqueued: enqueued)
    end
  end
end
