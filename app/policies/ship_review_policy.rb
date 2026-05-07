# frozen_string_literal: true

class ShipReviewPolicy < ApplicationPolicy
  def index? = user&.can_review?

  def show? = user&.can_review?

  def update?
    return false unless user&.can_review?
    record.reviewer_id == user.id
  end

  def next? = user&.can_review?

  def claim? = user&.can_review?

  class Scope < ApplicationPolicy::Scope
    def resolve
      user&.can_review? ? scope.all : scope.none
    end
  end
end
