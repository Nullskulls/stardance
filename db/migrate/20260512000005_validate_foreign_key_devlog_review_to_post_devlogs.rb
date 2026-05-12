class ValidateForeignKeyDevlogReviewToPostDevlogs < ActiveRecord::Migration[8.1]
  def change
    validate_foreign_key :post_devlogs, :devlog_reviews, column: :devlog_review_id
  end
end
