module Admin
  class ReviewsController < Admin::ApplicationController
    def index
      authorize :admin, :access_reviews?

      @reviews = YswsReview
        .where(reviewed_at: nil)
        .includes(:project, :user)
        .order(created_at: :asc)
    end

    def show
      authorize :admin, :access_reviews?

      @review = YswsReview
        .includes(:project, :user, :reviewer, devlog_reviews: { post_devlog: :attachments_attachments })
        .find(params[:id])

      # Calculate time stats
      devlog_minutes = @review.devlog_reviews.map(&:original_minutes).compact

      @stats = {
        total_minutes: devlog_minutes.sum,
        avg_minutes: devlog_minutes.any? ? (devlog_minutes.sum.to_f / devlog_minutes.count) : 0,
        max_minutes: devlog_minutes.max || 0,
        one_hour_plus_count: devlog_minutes.count { |m| m >= 60 }
      }
    end
  end
end