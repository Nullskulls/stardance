# == Schema Information
#
# Table name: devlog_reviews
#
#  id               :bigint           not null, primary key
#  approved_minutes :integer
#  justification    :text
#  original_minutes :integer
#  created_at       :datetime         not null
#  updated_at       :datetime         not null
#  post_devlog_id   :bigint           not null
#  ysws_review_id   :bigint           not null
#
# Indexes
#
#  index_devlog_reviews_on_post_devlog_id  (post_devlog_id)
#  index_devlog_reviews_on_ysws_review_id  (ysws_review_id)
#
# Foreign Keys
#
#  fk_rails_...  (post_devlog_id => post_devlogs.id)
#  fk_rails_...  (ysws_review_id => ysws_reviews.id)
#
class DevlogReview < ApplicationRecord
  belongs_to :post_devlog, class_name: "Post::Devlog"
  belongs_to :ysws_review

  validates :original_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
  validates :approved_minutes, numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
