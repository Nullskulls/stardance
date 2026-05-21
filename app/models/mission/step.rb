# == Schema Information
#
# Table name: mission_steps
#
#  id         :bigint           not null, primary key
#  body       :text             not null
#  deleted_at :datetime
#  position   :integer          not null
#  title      :string           not null
#  created_at :datetime         not null
#  updated_at :datetime         not null
#  mission_id :bigint           not null
#
# Indexes
#
#  index_mission_steps_on_deleted_at               (deleted_at)
#  index_mission_steps_on_mission_id               (mission_id)
#  index_mission_steps_on_mission_id_and_position  (mission_id,position)
#
# Foreign Keys
#
#  fk_rails_...  (mission_id => missions.id)
#
class Mission::Step < ApplicationRecord
  self.table_name = "mission_steps"

  include SoftDeletable

  has_paper_trail

  belongs_to :mission, inverse_of: :steps, counter_cache: true
  has_many :step_completions, class_name: "Mission::StepCompletion",
                              foreign_key: :mission_step_id,
                              dependent: :destroy

  validates :title, presence: true
  validates :body, presence: true
  validates :position, presence: true, numericality: { only_integer: true }

  scope :ordered, -> { order(:position, :id) }
end
