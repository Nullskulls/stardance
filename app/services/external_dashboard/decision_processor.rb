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

      cert = find_cert
      return error(:not_found, "cert not found (externalId=#{certification[:externalId].inspect} id=#{certification[:id].inspect})") if cert.nil?

      if proof_video_url
        return error(:bad_request, "proofVideoUrl must be an http(s) URL") unless proof_video_url.match?(%r{\Ahttps?://\S+\z})
        return error(:bad_request, "proofVideoUrl exceeds #{Post::ShipEvent::FEEDBACK_VIDEO_URL_MAX_LENGTH} chars") if proof_video_url.length > Post::ShipEvent::FEEDBACK_VIDEO_URL_MAX_LENGTH
      end

      apply(cert)
    end

    private

    attr_reader :payload

    def apply(cert)
      target_status = Certification::Ship::EXTERNAL_DECISION_MAP.fetch(decision_status)
      result = nil

      PaperTrail.request(whodunnit: whodunnit) do
        cert.with_lock do
          cert.reload

          if cert.pending?
            apply_decision!(cert, target_status)
            result = ok(decision_payload(cert.reload, idempotent: false))
            next
          end

          if cert.status.to_sym == target_status
            cert.assign_external_certification_id!(certification[:id])
          else
            log_divergence(cert, target_status)
          end
          result = ok(decision_payload(cert, idempotent: true))
        end
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

    def find_cert
      uuid = certification[:id].to_s
      if uuid.match?(Certification::Ship::EXTERNAL_CERTIFICATION_ID_PATTERN)
        by_uuid = Certification::Ship.find_by(external_certification_id: uuid)
        return by_uuid if by_uuid
      end

      cert_id = parse_cert_id
      cert_id && Certification::Ship.find_by(id: cert_id)
    end

    def parse_cert_id
      raw = certification[:externalId].to_s
      return nil if raw.length > EXTERNAL_ID_MAX_LENGTH
      match = raw.match(EXTERNAL_ID_PATTERN)
      match && match[1].to_i
    end

    def reviewer
      return @reviewer if defined?(@reviewer)
      slack_id = certification[:reviewerSlackId].to_s.presence
      @reviewer = slack_id && User.find_by(slack_id: slack_id)
    end

    def whodunnit
      reviewer&.id&.to_s || "external_dashboard"
    end

    def reviewer_comment
      certification[:reviewerComment].to_s.presence&.truncate(Post::ShipEvent::FEEDBACK_REASON_MAX_LENGTH, omission: "")
    end

    def proof_video_url
      certification[:proofVideoUrl].to_s.presence
    end

    def apply_decision!(cert, target_status)
      ship_event = cert.project&.last_ship_event
      ship_event&.update!(
        certification_status: target_status.to_s,
        feedback_reason: reviewer_comment,
        feedback_video_url: proof_video_url
      )
      cert.update!(status: target_status, feedback: reviewer_comment, reviewer_id: reviewer&.id)
      cert.assign_external_certification_id!(certification[:id])
    end

    def decision_payload(cert, idempotent:)
      {
        idempotent: idempotent,
        ship_review: { id: cert.id, status: cert.status, project_id: cert.project_id, external_certification_id: cert.external_certification_id }
      }
    end

    def ok(body)
      Result.new(status: :ok, body: body)
    end

    def error(status_sym, message)
      Rails.logger.warn "[ExternalDashboard::DecisionProcessor] #{status_sym} #{message}"
      Result.new(status: status_sym, body: { error: message })
    end

    def log_divergence(cert, target_status)
      Rails.logger.warn(
        "[ExternalDashboard::DecisionProcessor] divergent decision " \
        "cert=#{cert.id} local=#{cert.status} remote=#{target_status} — keeping local"
      )
    end
  end
end
