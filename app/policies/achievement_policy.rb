class AchievementPolicy < ApplicationPolicy
  def index?
    signed_in_any?
  end
end
