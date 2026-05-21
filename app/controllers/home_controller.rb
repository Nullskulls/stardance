class HomeController < ApplicationController
  def index
    authorize :home
    @body_class = "app-layout-page"
    @welcoming = params[:welcome] == "1" && current_user.present? && !session[:welcomed]
    @body_class += " home-welcoming" if @welcoming

    session[:welcomed] = true if @welcoming

    load_feed
    load_composer
    load_recommended_projects
  end

  private

  def load_feed
    posts = Post.of_devlogs(join: true)
                .where(post_devlogs: { deleted_at: nil })
                .includes(:user, :project, devlog: { attachments_attachments: :blob })
                .order(created_at: :desc)
                .limit(20)

    @feed_posts = posts.select { |post| post.postable.present? }
    @liked_devlog_ids = liked_devlog_ids_for(@feed_posts)
  end

  def liked_devlog_ids_for(posts)
    devlog_ids = posts.map(&:postable_id)
    return Set.new if devlog_ids.empty?

    Like.where(user: current_user, likeable_type: "Post::Devlog", likeable_id: devlog_ids).pluck(:likeable_id).to_set
  end

  def load_composer
    @devlog = Post::Devlog.new
    @composer_projects = current_user.projects.order(updated_at: :desc)
    @selected_project = selected_composer_project
  end

  def selected_composer_project
    if params[:project_id].present?
      @composer_projects.find_by(id: params[:project_id]) || @composer_projects.first
    else
      @composer_projects.first
    end
  end

  def load_recommended_projects
    @recommended_projects = Project.excluding_member(current_user)
                                   .where(deleted_at: nil)
                                   .with_banner_priority
                                   .limit(6)
  end
end
