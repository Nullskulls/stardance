module ExternalDashboard
  module BackfillRun
    extend self

    TTL = 7.days
    LAST_RUN_KEY = "external_dashboard:backfill:last_run_id".freeze
    RUN_ID_PATTERN = /\A\d{14}-\h{4}\z/

    def start(enqueued:)
      run_id = "#{Time.current.utc.strftime('%Y%m%d%H%M%S')}-#{SecureRandom.hex(2)}"
      Rails.cache.increment(key(run_id, "enqueued"), enqueued, expires_in: TTL)
      run_id
    end

    def record_enqueued(run_id)
      return if run_id.blank?

      Rails.cache.increment(key(run_id, "enqueued"), 1, expires_in: TTL)
    end

    def run_id_from(arguments)
      arguments.find { |arg| arg.is_a?(Hash) }&.dig(:backfill_run_id)
    end

    def remember_last_run(run_id)
      Rails.cache.write(LAST_RUN_KEY, run_id, expires_in: TTL)
    end

    def last_run_id
      Rails.cache.read(LAST_RUN_KEY)
    end

    def report(run_id)
      counts = SyncEvent.where(run_id: run_id).group(:outcome).count
      {
        run_id: run_id,
        enqueued: Rails.cache.read(key(run_id, "enqueued"), raw: true).to_i,
        ok: counts["ok"].to_i,
        duplicate: counts["duplicate"].to_i,
        skipped: counts["skipped"].to_i,
        failed: counts["failed"].to_i,
        retrying: counts["retrying"].to_i
      }
    end

    private

    def key(run_id, counter)
      "external_dashboard:backfill:#{run_id}:#{counter}"
    end
  end
end
