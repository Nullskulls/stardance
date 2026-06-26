module ExternalDashboard
  class CertIdBackfillService
    APPROVED_PATH = "/api/v1/certifications/approved".freeze
    EXTERNAL_ID_PREFIX = ExternalDashboard::ShipWebhookService::EXTERNAL_ID_PREFIX
    TIMEOUT_SECONDS = 30

    Result = Struct.new(:status, :total, :persisted, :skipped, :error, keyword_init: true) do
      def ok? = status == :ok
    end

    def self.call(refetch: true)
      new(refetch: refetch).call
    end

    def initialize(refetch:)
      @refetch = refetch
    end

    def call
      return Result.new(status: :not_configured, total: 0, persisted: 0, skipped: 0, error: "api key or workplace id missing") unless ExternalDashboard::ShipWebhookService.configured?

      response = connection.get(APPROVED_PATH, refetch_param)
      return remote_error(response) unless response.status.between?(200, 299)

      certs = parse_certs(response.body)
      total = certs.size
      persisted = 0
      skipped = 0

      certs.each do |cert|
        result = persist(cert)
        result == :persisted ? persisted += 1 : skipped += 1
      end

      Rails.logger.info "[ExternalDashboard::CertIdBackfillService] total=#{total} persisted=#{persisted} skipped=#{skipped}"
      Result.new(status: :ok, total: total, persisted: persisted, skipped: skipped)
    end

    private

    def connection
      Faraday.new(url: ExternalDashboard::ShipWebhookService.base_url) do |conn|
        conn.options.timeout = TIMEOUT_SECONDS
        conn.options.open_timeout = TIMEOUT_SECONDS
        conn.headers["x-api-key"] = ExternalDashboard::ShipWebhookService.api_key.to_s
        conn.headers["x-workplace-id"] = ExternalDashboard::ShipWebhookService.workplace_id.to_s
        conn.adapter Faraday.default_adapter
      end
    end

    def refetch_param
      @refetch ? { refetch: true } : {}
    end

    def parse_certs(raw)
      body = JSON.parse(raw.to_s)
      Array(body["certifications"])
    rescue JSON::ParserError
      []
    end

    def persist(cert)
      external_id = cert["externalId"].to_s
      return :skipped unless external_id.start_with?(EXTERNAL_ID_PREFIX)

      ship_event_id = external_id.delete_prefix(EXTERNAL_ID_PREFIX).to_i
      return :skipped if ship_event_id.zero?

      ship_event = Post::ShipEvent.find_by(id: ship_event_id)
      return :skipped if ship_event.nil?

      ship_event.assign_external_certification_id!(cert["id"])
    end

    def remote_error(response)
      Rails.logger.warn "[ExternalDashboard::CertIdBackfillService] remote error http=#{response.status} body=#{response.body.to_s.truncate(500)}"
      Result.new(status: :remote_error, total: 0, persisted: 0, skipped: 0, error: "http #{response.status}")
    end
  end
end
