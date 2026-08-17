module ExternalDashboard
  class ProjectBountyProcessor
    TEST_CONNECTION_ID = "test".freeze

    Result = Struct.new(:status, :body, keyword_init: true)

    def self.call(payload)
      new(payload).call
    end

    def initialize(payload)
      @payload = (payload || {}).with_indifferent_access
    end

    def call
      return ok_test if cert_id_param == TEST_CONNECTION_ID
      return error(:bad_request, "missing certification object") unless certification.is_a?(Hash)
      return error(:bad_request, "invalid amount: #{payload[:amount].inspect}") if amount.nil?

      cert = find_cert
      return error(:not_found, "cert not found (externalId=#{certification[:externalId].inspect} id=#{certification[:id].inspect})") if cert.nil?
      return error(:conflict, "cert #{cert.id} is already decided — bounty can only be set while its review is pending") unless cert.pending?

      PaperTrail.request(whodunnit: whodunnit) { apply(cert) }
    end

    private

    attr_reader :payload

    def certification
      payload[:certification]
    end

    def cert_id_param
      certification.is_a?(Hash) ? certification[:id].to_s : payload[:id].to_s
    end

    def amount
      raw = payload[:amount].to_s
      return nil unless raw.match?(Client::STRICT_INTEGER_PATTERN)

      value = Integer(raw, 10, exception: false)
      value && value.between?(0, Project::MAX_BOUNTY_STARDUST) ? value : nil
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
      raw.match?(Client::EXTERNAL_ID_PATTERN) ? raw.to_i : nil
    end

    def setter
      return @setter if defined?(@setter)
      slack_id = payload[:setBy].to_s.presence
      @setter = slack_id && User.find_by(slack_id: slack_id)
    end

    def whodunnit
      setter&.id&.to_s || "external_dashboard"
    end

    def apply(cert)
      project = cert.project
      project.update!(bounty_stardust: amount)
      ok(bounty_payload(cert, project))
    end

    def bounty_payload(cert, project)
      {
        certification: { id: cert.external_certification_id, shipReviewId: cert.id },
        projectId: project.id,
        bountyStardust: project.bounty_stardust
      }
    end

    def ok(body)
      Result.new(status: :ok, body: body)
    end

    def ok_test
      Result.new(status: :ok, body: { status: "ok", test: true })
    end

    def error(status_sym, message)
      Rails.logger.warn "[ExternalDashboard::ProjectBountyProcessor] #{status_sym} #{message}"
      Result.new(status: status_sym, body: { error: message })
    end
  end
end
