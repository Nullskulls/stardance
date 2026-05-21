class My::BalancesController < ApplicationController
  def show
    authorize :my, :show_balance?

    unless turbo_frame_request?
      redirect_to root_path
      return
    end

    @balance = current_user.ledger_entries.includes(:ledgerable).order(created_at: :desc)
    render "my/balance"
  end
end
