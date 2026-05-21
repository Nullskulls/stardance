class My::DismissalsController < ApplicationController
  def create
    authorize :my, :create_dismissal?

    if params[:thing_name].present?
      current_user.dismiss_thing!(params[:thing_name])
      head :ok
    else
      head :bad_request
    end
  rescue StandardError => e
    Rails.logger.error("Error dismissing thing: #{e.message}")
    head :internal_server_error
  end
end
