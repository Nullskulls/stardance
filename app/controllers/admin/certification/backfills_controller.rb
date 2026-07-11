class Admin::Certification::BackfillsController < Admin::Certification::ApplicationController
  WIPE_CONFIRMATION = "WIPE".freeze

  def show
    authorize :admin, :manage_external_sync?

    @run_id = params[:run_id].presence || ExternalDashboard::BackfillRun.last_run_id
    @report = @run_id && ExternalDashboard::ShipBackfillService.report(@run_id)
    @in_flight = SolidQueue::Job.where(
      class_name: %w[ExternalDashboard::ShipWebhookJob ExternalDashboard::CertReturnJob],
      finished_at: nil
    ).count
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

    cleared = ExternalDashboard::ShipBackfillService.reset_external_ids!
    Rails.logger.info "[Admin::Certification::Backfills] wiped external ids from #{cleared} certs triggered_by=#{current_user.id}"
    redirect_to admin_certification_backfill_path, notice: "Wiped dashboard UUIDs from #{cleared} certs."
  end
end
