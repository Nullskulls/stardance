class OnboardingPolicy < ApplicationPolicy
  def complete?
    signed_in_any?
  end
end
