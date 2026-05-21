# == Schema Information
#
# Table name: missions
#
#  id                      :bigint           not null, primary key
#  achievement_description :text
#  achievement_name        :string
#  deleted_at              :datetime
#  description             :text             not null
#  difficulty              :string
#  enabled                 :boolean          default(TRUE), not null
#  end_at                  :datetime
#  featured_at             :datetime
#  name                    :string           not null
#  prizes_count            :integer          default(0), not null
#  slug                    :string           not null
#  start_at                :datetime
#  steps_count             :integer          default(0), not null
#  created_at              :datetime         not null
#  updated_at              :datetime         not null
#
# Indexes
#
#  index_missions_on_deleted_at   (deleted_at)
#  index_missions_on_enabled      (enabled)
#  index_missions_on_featured_at  (featured_at)
#  index_missions_on_slug         (slug) UNIQUE
#
class Mission < ApplicationRecord
  include SoftDeletable

  has_paper_trail

  has_one_attached :icon
  has_one_attached :banner

  has_many :steps, class_name: "Mission::Step", dependent: :destroy
  has_many :prizes, class_name: "Mission::Prize", dependent: :destroy
  has_many :memberships, class_name: "Mission::Membership", dependent: :destroy
  has_many :shop_unlocks, class_name: "Mission::ShopUnlock", dependent: :destroy
  has_many :submissions, class_name: "Mission::Submission", dependent: :destroy
  has_many :attachments, class_name: "Project::MissionAttachment", dependent: :destroy
  has_many :projects, through: :attachments

  has_many :owners,    -> { where(mission_memberships: { role: :owner }) },
           through: :memberships, source: :user
  has_many :reviewers, -> { where(mission_memberships: { role: :reviewer }) },
           through: :memberships, source: :user

  DIFFICULTIES = %w[beginner intermediate advanced].freeze
  enum :difficulty, DIFFICULTIES.index_with(&:itself), prefix: true

  validates :slug, presence: true, uniqueness: true,
                   format: { with: /\A[a-z0-9][a-z0-9_-]*\z/, message: "must be URL-safe" }
  validates :name, presence: true
  validates :description, presence: true

  scope :enabled,  -> { where(enabled: true) }
  scope :featured, -> { where.not(featured_at: nil) }

  scope :available, -> {
    enabled
      .where("start_at IS NULL OR start_at <= ?", Time.current)
      .where("end_at   IS NULL OR end_at   > ?", Time.current)
  }

  def started? = start_at.nil? || start_at <= Time.current
  def ended?   = end_at.present? && end_at <= Time.current
  def coming_soon? = !started?

  def available_to_builders?
    enabled? && started? && !ended?
  end

  def has_steps?  = steps.any?
  def has_prizes? = prizes.any?

  # Per-mission achievement slug. Nil when no achievement is configured (admin
  # left achievement_name blank).
  def achievement_slug
    return nil if achievement_name.blank?
    "mission_#{slug}_completed"
  end
end
