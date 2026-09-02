module ExternalDashboard
  # Shared by the inbound decision webhook and the reconciliation poller, so
  # there's one implementation of the lock/idempotency/divergence logic.
  class VerdictApplier
    REPLAY_CLOCK_SKEW = 5.minutes
    DIVERGENCE_SENTRY_MESSAGE = "ExternalDashboard verdict diverges from local decision".freeze
    DIVERGENCE_ALERT_TTL = 1.day

    Outcome = Struct.new(:status, :cert, keyword_init: true)

    def self.call(...) = new(...).call

    def self.stale?(cert:, decided_at:)
      decided_at.present? && decided_at < (cert.created_at - REPLAY_CLOCK_SKEW)
    end

    def initialize(cert:, target_status:, reviewer: nil, comment: nil, proof_video_url: nil, external_uuid: nil, decided_at: nil, dry_run: false)
      @cert = cert
      @target_status = target_status
      @reviewer = reviewer
      @comment = comment
      @proof_video_url = proof_video_url
      @external_uuid = external_uuid
      @decided_at = decided_at
      @dry_run = dry_run
    end

    def call
      outcome = nil
      PaperTrail.request(whodunnit: whodunnit) do
        ActiveRecord::Base.transaction(requires_new: true) do
          cert.with_lock { outcome = apply_locked }
          raise ActiveRecord::Rollback if dry_run
        end
      end
      outcome
    end

    private

    attr_reader :cert, :target_status, :reviewer, :comment, :proof_video_url, :external_uuid, :decided_at, :dry_run

    def apply_locked
      return stale_outcome if cert.pending? && self.class.stale?(cert: cert, decided_at: decided_at)

      if cert.pending?
        apply!
        Outcome.new(status: :applied, cert: cert)
      elsif cert.status.to_sym == target_status
        cert.assign_external_certification_id!(external_uuid)
        Outcome.new(status: :idempotent, cert: cert)
      else
        log_divergence
        Outcome.new(status: :divergent, cert: cert)
      end
    end

    def apply!
      cert.update!(status: target_status, feedback: comment, reviewer_id: reviewer&.id, proof_video_url: proof_video_url)
      cert.assign_external_certification_id!(external_uuid)
    end

    def stale_outcome
      Rails.logger.warn "[ExternalDashboard::VerdictApplier]#{dry_run_tag} cert=#{cert.id} decision predates this review cycle (decided_at=#{decided_at})"
      Outcome.new(status: :stale, cert: cert)
    end

    def log_divergence
      Rails.logger.warn "[ExternalDashboard::VerdictApplier]#{dry_run_tag} cert=#{cert.id} already #{cert.status} locally — refusing remote #{target_status}"
      return if dry_run

      # The poller re-checks every cert in its lookback window on every run, so
      # an unresolved divergence would otherwise re-page on every cycle.
      alert_key = "external_dashboard:verdict_applier:divergence:#{cert.id}:#{cert.status}:#{target_status}"
      return if Rails.cache.exist?(alert_key)

      Rails.cache.write(alert_key, true, expires_in: DIVERGENCE_ALERT_TTL)
      Sentry.capture_message(
        DIVERGENCE_SENTRY_MESSAGE,
        level: :warning,
        extra: { cert_id: cert.id, local_status: cert.status, remote_status: target_status.to_s }
      )
    end

    def dry_run_tag
      dry_run ? " [dry-run]" : ""
    end

    def whodunnit
      reviewer&.id&.to_s || "external_dashboard"
    end
  end
end
