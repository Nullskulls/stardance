module ExternalDashboard
  class SyncStats
    RECENT_FAILURES_LIMIT = 15
    BREAKDOWN_LIMIT = 10
    RECENT_WINDOW = 24.hours

    def self.call
      new.call
    end

    def call
      certs = Certification::Ship.all
      unsynced = certs.where(external_certification_id: nil)

      {
        total: certs.count,
        synced: certs.where.not(external_certification_id: nil).count,
        unsynced: unsynced.count,
        eligible: ShipBackfillService.eligible_scope.count,
        unsynced_hardware: unsynced.joins(:project).where.not(projects: { hardware_stage: [ nil, "" ] }).count,
        unsynced_deleted: unsynced.left_joins(:project).where(projects: { id: nil }).count,
        unsynced_active_returns: ShipBackfillService.active_returns.where(external_certification_id: nil).count,
        synced_recently: certs.where(external_sync_error: nil)
                              .where(external_sync_attempted_at: RECENT_WINDOW.ago..).count,
        failed_recently: certs.where.not(external_sync_error: nil)
                              .where(external_sync_attempted_at: RECENT_WINDOW.ago..).count,
        recent_failures: certs.where.not(external_sync_error: nil)
                              .order(external_sync_attempted_at: :desc)
                              .includes(:project).limit(RECENT_FAILURES_LIMIT),
        failure_breakdown: unsynced.where.not(external_sync_error: nil)
                                   .group(:external_sync_error).count
                                   .sort_by { |_error, count| -count }
                                   .first(BREAKDOWN_LIMIT)
      }
    end
  end
end
