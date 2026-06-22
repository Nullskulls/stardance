# == Schema Information
#
# Table name: votes
#
#  id                 :bigint           not null, primary key
#  originality_score  :integer
#  reason             :text
#  storytelling_score :integer
#  technical_score    :integer
#  usability_score    :integer
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  project_id         :bigint           not null
#  ship_event_id      :bigint           not null
#  user_id            :bigint           not null
#
# Indexes
#
#  index_votes_on_project_id                 (project_id)
#  index_votes_on_ship_event_id              (ship_event_id)
#  index_votes_on_user_id                    (user_id)
#  index_votes_on_user_id_and_ship_event_id  (user_id,ship_event_id) UNIQUE
#
# Foreign Keys
#
#  fk_rails_...  (project_id => projects.id)
#  fk_rails_...  (ship_event_id => post_ship_events.id)
#  fk_rails_...  (user_id => users.id)
#
class Vote < ApplicationRecord
  FLAG_COST = 5
  MIN_SCORE = 1
  MAX_SCORE = 9

  CATEGORIES = {
    originality: "How distinct is the project from common projects?",
    technicality: "How much effort did the creator put into the implementation?",
    usability: "Did you like using it? Could you use it at all?",
    storytelling: "How well does the creator document the development journey through devlogs, documentation, commit messages, and READMEs?"
  }.freeze

  SCORE_COLUMNS_BY_CATEGORY = {
    originality: :originality_score,
    technicality: :technical_score,
    usability: :usability_score,
    storytelling: :storytelling_score
  }.freeze

  def self.score_columns = SCORE_COLUMNS_BY_CATEGORY.values

  def self.countable_count_sql
    <<~SQL.squish
      SELECT COUNT(*)
      FROM votes
      WHERE votes.ship_event_id = post_ship_events.id
        AND NOT EXISTS (
          SELECT 1
          FROM vote_events
          WHERE vote_events.vote_id = votes.id
            AND vote_events.event_type = 'vote_flag_accepted'
        )
    SQL
  end

  belongs_to :user, counter_cache: true
  belongs_to :project
  belongs_to :ship_event, class_name: "Post::ShipEvent", counter_cache: true

  has_one :assignment, class_name: "Vote::Assignment", dependent: :nullify
  has_many :events, class_name: "Vote::Event", inverse_of: :vote, dependent: :nullify

  has_paper_trail on: [ :create, :update, :destroy ]

  after_commit :increment_user_vote_balance, on: :create
  after_commit :refresh_ship_event_payout_later, on: [ :create, :destroy ]
  after_create_commit :send_gorse_vote_later

  scope :payout_countable, -> { where.not(id: Vote::Event.accepted_vote_flags.select(:vote_id)) }

  validates :reason, presence: true
  validate :reason_minimum_words
  validates(*score_columns,
    presence: { message: "must be scored" },
    numericality: { only_integer: true, in: MIN_SCORE..MAX_SCORE, message: "must be between #{MIN_SCORE} and #{MAX_SCORE}" })
  validate :user_cannot_vote_on_own_projects
  validate :ship_event_matches_project

  def flaggable_by?(user)
    user.present? &&
      ship_event&.payout_review_open? &&
      project&.memberships&.where(role: :owner, user: user)&.exists? &&
      !pending_flag? &&
      !discarded?
  end

  def flag_for_review_by(user)
    if flaggable_by?(user)
      events.create!(
        event_type: "vote_flagged",
        user: user,
        project: project,
        ship_event: ship_event,
        properties: { status: "pending" }
      )
    else
      false
    end
  end

  def accept_flag(reviewer:)
    if pending_flag = self.pending_flag
      transaction do
        events.create!(
          event_type: "vote_flag_accepted",
          user: reviewer,
          project: project,
          ship_event: ship_event,
          properties: { flagged_event_id: pending_flag.id }
        )
        ship_event.clear_payout_review
      end
    else
      false
    end
  end

  def reject_flag(reviewer:)
    if pending_flag = self.pending_flag
      transaction do
        events.create!(
          event_type: "vote_flag_rejected",
          user: reviewer,
          project: project,
          ship_event: ship_event,
          properties: { flagged_event_id: pending_flag.id }
        )
        pending_flag.user.ledger_entries.create!(
          ledgerable: self,
          amount: -FLAG_COST,
          reason: "Incorrect vote flag: #{project&.title || 'Unknown project'}",
          created_by: "vote_flag_review"
        )
        ship_event.issue_payout(force: true)
      end
    else
      false
    end
  end

  def pending_flag
    events
      .where(event_type: "vote_flagged")
      .where.not(vote_id: Vote::Event.resolved_vote_flags.select(:vote_id))
      .order(created_at: :asc)
      .last
  end

  def pending_flag? = pending_flag.present?

  def discarded? = events.exists?(event_type: "vote_flag_accepted")

  private

  # Validations

  def reason_minimum_words
    return if reason.blank?

    word_count = reason.split(/\s+/).count
    errors.add(:reason, "must be at least 10 words (you have #{word_count})") if word_count < 10
  end

  def user_cannot_vote_on_own_projects
    errors.add(:user, "cannot vote on own projects") if project&.users&.exists?(user_id)
  end

  def ship_event_matches_project
    return if ship_event.blank? || project_id.blank?

    expected_project_id = ship_event.post&.project_id
    return if expected_project_id.blank?

    errors.add(:project, "does not match ship event") if project_id != expected_project_id
  end

  # Callback

  def increment_user_vote_balance
    user.increment!(:vote_balance, 1)
  end

  def refresh_ship_event_payout_later
    ShipEventPayoutRefreshJob.perform_later
  end

  def send_gorse_vote_later
    if ship_event&.post.present?
      send_gorse_feedback_later(
        user: user,
        item: ship_event.post,
        feedback_type: :vote,
        value: score_average,
        timestamp: created_at
      )
    end
  end

  def score_average
    scores = self.class.score_columns.filter_map { |column| public_send(column) }
    if scores.any?
      scores.sum.to_f / scores.size
    else
      1
    end
  end
end
