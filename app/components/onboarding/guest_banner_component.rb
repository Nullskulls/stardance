module Onboarding
  class GuestBannerComponent < ViewComponent::Base
    GRACE_PERIOD = 1.day

    def render?
      user = helpers.current_user
      return false unless user&.guest?
      user.created_at < GRACE_PERIOD.ago
    end
  end
end
