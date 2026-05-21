class IdentityPolicy < ApplicationPolicy
  def hackatime?
    signed_in_any?
  end
end
