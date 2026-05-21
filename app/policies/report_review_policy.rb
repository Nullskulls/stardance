class ReportReviewPolicy < ApplicationPolicy
  def review?
    signed_in_any?
  end

  def dismiss?
    signed_in_any?
  end
end
