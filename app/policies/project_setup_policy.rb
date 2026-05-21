class ProjectSetupPolicy < ApplicationPolicy
  def idea?         = signed_in_any?
  def submit_idea?  = signed_in_any?
  def name?         = signed_in_any?
  def submit_name?  = signed_in_any?
  def missions?     = signed_in_any?
  def submit_mission? = signed_in_any?
  def link_account? = signed_in_any?
  def welcome?      = signed_in_any?
end
