module ExternalDashboard
  class ShipWebhookService
    DEFAULT_BASE_URL = "https://dash.shipwrights.dev".freeze
    INGEST_PATH = "/api/v1/certifications/ingest".freeze
    TIMEOUT_SECONDS = 10
    EXTERNAL_ID_PREFIX = "SD-".freeze
    ERROR_MESSAGE_MAX = 500

    Result = Struct.new(:status, :cert_id, :http_status, :error, keyword_init: true) do
      def ok?       = status == :ok
      def duplicate? = status == :duplicate
    end

    def self.call(ship_event)
      new(ship_event).call
    end

    def self.configured?
      api_key.present? && workplace_id.present?
    end

    def self.base_url
      Rails.application.credentials.dig(:external_dashboard, :base_url) ||
        ENV["EXTERNAL_DASHBOARD_BASE_URL"].presence ||
        DEFAULT_BASE_URL
    end

    def self.api_key
      Rails.application.credentials.dig(:external_dashboard, :api_key) ||
        ENV["EXTERNAL_DASHBOARD_API_KEY"]
    end

    def self.workplace_id
      Rails.application.credentials.dig(:external_dashboard, :workplace_id) ||
        ENV["EXTERNAL_DASHBOARD_WORKPLACE_ID"]
    end

    def self.connection
      Faraday.new(url: base_url) do |conn|
        conn.options.timeout = TIMEOUT_SECONDS
        conn.options.open_timeout = TIMEOUT_SECONDS
        conn.headers["Content-Type"] = "application/json"
        conn.headers["x-api-key"] = api_key.to_s
        conn.headers["x-workplace-id"] = workplace_id.to_s
        conn.adapter Faraday.default_adapter
      end
    end

    def initialize(ship_event)
      @ship_event = ship_event
    end

    def call
      return Result.new(status: :not_configured, error: "api key or workplace id missing") unless self.class.configured?
      return Result.new(status: :skipped, error: "ship_event has no project") if project.nil?
      return Result.new(status: :skipped, error: "owner has no slack_id") if owner_slack_id.blank?

      response = self.class.connection.post(INGEST_PATH, payload.to_json)
      parse_response(response)
    end

    private

    attr_reader :ship_event

    def project
      @project ||= ship_event.project
    end

    def owner
      @owner ||= project&.memberships&.owner&.order(:created_at)&.first&.user
    end

    def owner_slack_id
      owner&.slack_id.presence
    end

    def payload
      {
        id: "#{EXTERNAL_ID_PREFIX}#{ship_event.id}",
        projectName: project&.title,
        projectType: project&.hardware? ? "Hardware" : "Software",
        shipType: ship_type,
        description: project&.description.presence,
        aiDeclaration: project&.ai_declaration.presence,
        submittedBy: submitted_by.presence,
        links: links.presence,
        metadata: { devTime: dev_time_seconds }
      }.compact
    end

    def ship_type
      return "initial" unless project

      previously_approved = project.posts
        .joins("INNER JOIN post_ship_events ON posts.postable_id = post_ship_events.id AND posts.postable_type = 'Post::ShipEvent'")
        .where(post_ship_events: { certification_status: "approved" })
        .where.not(post_ship_events: { id: ship_event.id })
        .exists?

      previously_approved ? "recertification" : "initial"
    end

    def submitted_by
      {
        slackId: owner_slack_id,
        username: owner&.display_name.presence
      }.compact
    end

    def links
      {
        demo: project&.demo_url.presence,
        repo: project&.repo_url.presence,
        readme: project&.readme_url.presence
      }.compact
    end

    def dev_time_seconds
      ((ship_event.hours_at_ship || 0) * 3600).to_i
    end

    def parse_response(response)
      body = parse_body(response.body)
      cert_id = body["certId"]
      error = body["error"].to_s.truncate(ERROR_MESSAGE_MAX).presence

      case response.status
      when 200..299
        Result.new(status: :ok, cert_id: cert_id, http_status: response.status)
      when 409
        Result.new(status: :duplicate, cert_id: cert_id, http_status: response.status)
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
