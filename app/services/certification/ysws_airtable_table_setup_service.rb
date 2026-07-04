module Certification
  class YswsAirtableTableSetupService
    Result = Struct.new(:status, :table_id, :error, keyword_init: true)

    def self.call
      api_key = Rails.application.credentials.dig(:ysws_review, :airtable_api_key) ||
                Rails.application.credentials&.airtable&.api_key ||
                ENV["AIRTABLE_API_KEY"]
      base_id = Rails.application.credentials.dig(:ysws_review, :airtable_base_id) ||
                ENV["YSWS_REVIEW_AIRTABLE_BASE_ID"]
      table_name = Rails.application.credentials.dig(:ysws_review, :airtable_table_name) ||
                   ENV["YSWS_REVIEW_AIRTABLE_TABLE"] ||
                   "YSWS Project Submission"

      return Result.new(status: :not_configured, error: "api key or base id missing") if api_key.blank? || base_id.blank?

      response = Faraday.post("https://api.airtable.com/v0/meta/bases/#{base_id}/tables") do |req|
        req.headers["Authorization"] = "Bearer #{api_key}"
        req.headers["Content-Type"] = "application/json"
        req.options.timeout = 15
        req.body = { name: table_name, fields: fields }.to_json
      end

      body = begin
        JSON.parse(response.body.to_s)
      rescue JSON::ParserError
        {}
      end

      if response.success?
        Rails.logger.info "[#{name}] created table #{table_name.inspect} id=#{body['id']}"
        Result.new(status: :ok, table_id: body["id"])
      else
        error = (body.dig("error", "message") || body["error"] || response.body).to_s.truncate(500)
        Rails.logger.warn "[#{name}] http=#{response.status} error=#{error}"
        Result.new(status: :remote_error, error: "http #{response.status}: #{error}")
      end
    end

    def self.fields
      text = ->(field) { { name: field, type: "singleLineText" } }
      long = ->(field) { { name: field, type: "multilineText" } }
      url  = ->(field) { { name: field, type: "url" } }
      dt   = ->(field) { { name: field, type: "dateTime", options: { timeZone: "utc", dateFormat: { name: "iso" }, timeFormat: { name: "24hour" } } } }

      [
        text.("review_id"),
        text.("ship_cert_id"),
        text.("user_slack_id"),
        { name: "Email", type: "email" },
        text.("First Name"),
        text.("Last Name"),
        text.("user_display_name"),
        { name: "Birthday", type: "date", options: { dateFormat: { name: "iso" } } },
        text.("How did you hear about this?"),
        text.("Address (Line 1)"),
        text.("Address (Line 2)"),
        text.("City"),
        text.("State / Province"),
        text.("ZIP / Postal Code"),
        text.("Country"),
        text.("project_name"),
        long.("ai_declaration"),
        long.("project_update_description"),
        url.("Code URL"),
        url.("Playable URL"),
        url.("readme_url"),
        long.("Description"),
        { name: "Screenshot", type: "multipleAttachments" },
        text.("reviewer"),
        text.("ship_certifier"),
        dt.("reviewed_at"),
        dt.("ship_certed_at"),
        dt.("airtable_synced_at"),
        { name: "Optional - Override Hours Spent", type: "number", options: { precision: 2 } },
        long.("Optional - Override Hours Spent Justification"),
        long.("rejection_reason"),
        dt.("rejected_at"),
        dt.("ship_end"),
        dt.("ship_start"),
        text.("report_status"),
        { name: "flagged_double_dipped", type: "checkbox", options: { icon: "check", color: "greenBright" } },
        text.("Automation - YSWS Record ID")
      ]
    end
  end
end
