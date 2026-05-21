class UserPolicy < ApplicationPolicy
  def show?
    true
  end

  def update?
    user.present? && user.id == record.id
  end

  def follow?
    user.present? && user.hca_linked? && user.id != record.id
  end

  def followers?
    true
  end

  def following?
    true
  end

  def view_deleted_devlogs?
    user&.can_see_deleted_devlogs?
  end

  def impersonate?
    # must be admin or super_admin to impersonate
    return false unless user.admin? || user.super_admin?

    # cannot impersonate yourself
    return false if user.id == record.id

    # only super admins can impersonate admins
    if record.admin? && !user.super_admin?
      return false
    end

    true
  end
end
