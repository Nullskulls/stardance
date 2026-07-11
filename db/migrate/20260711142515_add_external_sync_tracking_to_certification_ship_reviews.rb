class AddExternalSyncTrackingToCertificationShipReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_ship_reviews, :external_sync_error, :string
    add_column :certification_ship_reviews, :external_sync_attempted_at, :datetime
  end
end
