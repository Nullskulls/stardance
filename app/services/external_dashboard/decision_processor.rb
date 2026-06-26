module ExternalDashboard
  class DecisionProcessor
    DECISION_EVENT = "certification.decision".freeze
    TEST_EVENT = "test".freeze
    EXTERNAL_ID_PREFIX = ExternalDashboard::Client::EXTERNAL_ID_PREFIX
    EXTERNAL_ID_MAX_LENGTH = 32
    EXTERNAL_ID_PATTERN = /\A#{Regexp.escape(EXTERNAL_ID_PREFIX)}(\d+)\z/

    Result = Struct.new(:status, :body, keyword_init: true) do
      def ok? = status == :ok
    end

    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = (payload || {}).with_indifferent_access
    end

    def call
      return ok(event: TEST_EVENT, received: true) if event == TEST_EVENT
      return error(:bad_request, "unsupported event: #{event.inspect}") unless event == DECISION_EVENT
      return error(:bad_request, "missing certification object") unless certification.is_a?(Hash)
      return error(:unprocessable_entity, "unsupported status: #{decision_status.inspect}") unless Certification::Ship::EXTERNAL_DECISION_MAP.key?(decision_status)

      ship_event_id = parse_ship_event_id
      return error(:bad_request, "invalid externalId (expected #{EXTERNAL_ID_PREFIX}<id>)") if ship_event_id.nil?

      ship_event = Post::ShipEvent.find_by(id: ship_event_id)
      return error(:not_found, "ship_event #{ship_event_id} not found") if ship_event.nil?

      project = ship_event.project
      return error(:unprocessable_entity, "ship_event #{ship_event_id} has no project") if project.nil?

      if proof_video_url
        return error(:bad_request, "proofVideoUrl must be an http(s) URL") unless proof_video_url.match?(%r{\Ahttps?://})
        return error(:bad_request, "proofVideoUrl exceeds #{Post::ShipEvent::FEEDBACK_VIDEO_URL_MAX_LENGTH} chars") if proof_video_url.length > Post::ShipEvent::FEEDBACK_VIDEO_URL_MAX_LENGTH
      end

      apply_within_lock(project, ship_event)
    end

    private

    attr_reader :payload

    def apply_within_lock(project, ship_event)
      target_status = Certification::Ship::EXTERNAL_DECISION_MAP.fetch(decision_status)
      result = nil

      project.with_lock do
        ship_event.reload

        review = project.ship_reviews.find_by(status: :pending)
        if review
          apply_decision!(review, ship_event, target_status)
          result = ok(decision_payload(ship_event, review: review.reload, idempotent: false))
          next
        end

        if Post::ShipEvent::FINAL_CERTIFICATION_STATUSES.include?(ship_event.certification_status)
          log_divergence(ship_event, target_status) unless ship_event.certification_status == target_status.to_s
          persist_external_certification_id(ship_event)
          result = ok(decision_payload(ship_event, review: nil, idempotent: true))
          next
        end

        result = error(:unprocessable_entity, "no pending ship review for project #{project.id}")
      end

      result
    end

    def event
      payload[:event].to_s
    end

    def certification
      payload[:certification]
    end

    def decision_status
      certification[:status].to_s
    end

    def parse_ship_event_id
      raw = certification[:externalId].to_s
      return nil if raw.length > EXTERNAL_ID_MAX_LENGTH
      match = raw.match(EXTERNAL_ID_PATTERN)
      match && match[1].to_i
    end

    def reviewer_comment
      certification[:reviewerComment].to_s.presence&.truncate(Post::ShipEvent::FEEDBACK_REASON_MAX_LENGTH, omission: "")
    end

    def proof_video_url
      certification[:proofVideoUrl].to_s.presence
    end

    def apply_decision!(review, ship_event, target_status)
      review.update!(status: target_status, feedback: reviewer_comment)
      ship_event.update!(
        feedback_reason: reviewer_comment,
        feedback_video_url: proof_video_url
      )
      persist_external_certification_id(ship_event)
    end

    def persist_external_certification_id(ship_event)
      ship_event.assign_external_certification_id!(certification[:id])
    end

    def decision_payload(ship_event, review:, idempotent:)
      {
        idempotent: idempotent,
        ship_event: { id: ship_event.id, certification_status: ship_event.certification_status },
        ship_review: review && { id: review.id, status: review.status, project_id: review.project_id }
      }
    end

    def ok(body)
      Result.new(status: :ok, body: body)
    end

    def error(status_sym, message)
      Rails.logger.warn "[ExternalDashboard::DecisionProcessor] #{status_sym} #{message}"
      Result.new(status: status_sym, body: { error: message })
    end

    def log_divergence(ship_event, target_status)
      Rails.logger.warn(
        "[ExternalDashboard::DecisionProcessor] divergent decision " \
        "ship_event=#{ship_event.id} local=#{ship_event.certification_status} remote=#{target_status} — keeping local"
      )
    end
  end
end
