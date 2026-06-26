module ExternalDashboard
  class CertReturnService
    Result = Struct.new(:status, :http_status, :error, keyword_init: true) do
      def ok? = status == :ok
    end

    def self.call(ship_event:, reason:)
      new(ship_event: ship_event, reason: reason).call
    end

    def initialize(ship_event:, reason:)
      @ship_event = ship_event
      @reason = reason.to_s.strip.truncate(Post::ShipEvent::RETURN_REASON_MAX_LENGTH, omission: "")
    end

    def call
      return Result.new(status: :not_configured, error: "api key or workplace id missing") unless Client.configured?
      return Result.new(status: :skipped, error: "ship_event has no external_certification_id") if cert_id.blank?
      return Result.new(status: :skipped, error: "reason is blank") if @reason.blank?

      response = Client.connection.post(path, { reason: @reason }.to_json)
      parse_response(response)
    end

    private

    def cert_id
      @ship_event.external_certification_id.to_s
    end

    def path
      "/api/v1/certifications/#{cert_id}/return"
    end

    def parse_response(response)
      body = parse_body(response.body)
      error = body["error"].to_s.truncate(Client::ERROR_MESSAGE_MAX).presence

      case response.status
      when 200..299
        Result.new(status: :ok, http_status: response.status)
      when 400..499
        Result.new(status: :client_error, http_status: response.status, error: error)
      else
        Result.new(status: :server_error, http_status: response.status, error: error)
      end
    end

    def parse_body(raw)
      JSON.parse(raw.to_s)
    rescue JSON::ParserError
      {}
    end
  end
end
