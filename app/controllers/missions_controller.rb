class MissionsController < ApplicationController
  before_action :set_body_class
  before_action :set_mission, only: [ :show ]

  def index
    authorize Mission

    @available_missions = Mission.available
                                 .includes(icon_attachment: :blob)
                                 .order(featured_at: :desc, name: :asc)
    @upcoming_missions = Mission.enabled
                                .where("start_at IS NOT NULL AND start_at > ?", Time.current)
                                .includes(icon_attachment: :blob)
                                .order(:start_at)
                                .limit(8)
    @ended_missions = Mission.enabled
                             .where("end_at IS NOT NULL AND end_at <= ?", Time.current)
                             .includes(icon_attachment: :blob)
                             .order(end_at: :desc)
                             .limit(8)
  end

  def show
    authorize @mission
    @ordered_steps = @mission.steps.ordered.to_a
    @ordered_prizes = @mission.prizes.ordered.includes(:shop_item).to_a
  end

  private

  def set_body_class
    @body_class = "app-layout-page"
  end

  def set_mission
    @mission = Mission.find_by!(slug: params[:slug])
  end
end
