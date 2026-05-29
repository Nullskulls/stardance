# frozen_string_literal: true

# Small `!` badge shown only to the owner on their own posts/profile when their
# identity isn't verified yet. The label is the hover text and explains that
# the surrounding content is hidden from other users until verification is
# done. Linking back to the profile IDV card means one place to act on it.
class IdvBadgeComponent < ViewComponent::Base
  attr_reader :user, :context

  CONTEXTS = %i[profile devlog post comment].freeze

  def initialize(user:, context: :devlog)
    @user = user
    @context = CONTEXTS.include?(context) ? context : :devlog
  end

  def render?
    user.present? && !user.identity_verified?
  end

  # Pending = under review (warning/amber); needs_submission or ineligible
  # (rejected/poor quality) = action needed (danger/red). Mirrors Flavortown's
  # id_verification_ui_for variants.
  def variant
    user.verification_pending? ? "warning" : "danger"
  end

  def tooltip
    subject = context == :profile ? "Your account" : "This #{context}"
    if user.verification_pending?
      "Your identity is under review. #{subject} will not be visible to the public until it's approved."
    elsif user.verification_ineligible?
      "Your identity verification didn't go through. #{subject} will stay private until it's sorted out."
    else
      "#{subject} is only visible to you and Hack Club admins until you verify your identity."
    end
  end
end
