class Admin::Certification::BackfillsController < Admin::Certification::ApplicationController
  WIPE_CONFIRMATION = "WIPE".freeze
  WEBHOOK_JOB_CLASSES = %w[ExternalDashboard::ShipWebhookJob ExternalDashboard::CertReturnJob].freeze

  def show
    authorize :admin, :manage_external_sync?

    requested = params[:run_id].presence
    requested = nil unless requested&.match?(ExternalDashboard::BackfillRun::RUN_ID_PATTERN)
    @run_id = requested || ExternalDashboard::BackfillRun.last_run_id
    @report = @run_id && ExternalDashboard::ShipBackfillService.report(@run_id)
    @in_flight = in_flight_count
  end

  def create
    authorize :admin, :manage_external_sync?

    result = ExternalDashboard::ShipBackfillService.call
    if result.status == :ok
      Rails.logger.info "[Admin::Certification::Backfills] run=#{result.run_id} enqueued=#{result.enqueued} triggered_by=#{current_user.id}"
      redirect_to admin_certification_backfill_path,
                  notice: "Backfill started (run #{result.run_id}) — #{result.enqueued} pushes queued."
    else
      redirect_to admin_certification_backfill_path, alert: "Backfill not started: #{result.error}"
    end
  end

  def wipe_uuids
    authorize :admin, :manage_external_sync?

    unless params[:confirmation].to_s.strip == WIPE_CONFIRMATION
      return redirect_to admin_certification_backfill_path,
                         alert: "Type #{WIPE_CONFIRMATION} in the confirmation field to wipe."
    end
    if in_flight_count.to_i.positive?
      return redirect_to admin_certification_backfill_path,
                         alert: "Dashboard jobs are still in flight — a job finishing after the wipe would write a stale UUID back. Wait for the queue to drain."
    end

    cleared = ExternalDashboard::ShipBackfillService.reset_external_ids!
    ::PaperTrail::Version.create!(
      item: current_user,
      event: "update",
      whodunnit: current_user.id.to_s,
      object_changes: { external_dashboard_uuid_wipe: [ nil, cleared ] }
    )
    Rails.logger.info "[Admin::Certification::Backfills] wiped external ids from #{cleared} certs triggered_by=#{current_user.id}"
    redirect_to admin_certification_backfill_path, notice: "Wiped dashboard UUIDs from #{cleared} certs."
  end

  private

  # The queue database only exists in production; elsewhere the page renders
  # without a queue depth. Failed executions keep finished_at nil while parked
  # for manual retry, so they're excluded or the count would never drain.
  def in_flight_count
    SolidQueue::Job.where(class_name: WEBHOOK_JOB_CLASSES, finished_at: nil)
                   .where.not(id: SolidQueue::FailedExecution.select(:job_id))
                   .count
  rescue ActiveRecord::StatementInvalid, ActiveRecord::NoDatabaseError, ActiveRecord::ConnectionNotEstablished
    nil
  end
end
