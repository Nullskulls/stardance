class HomePolicy < ApplicationPolicy
  def index?
    signed_in_any?
  end
end
