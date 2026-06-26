class MoveExternalCertificationIdToShipReviews < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    unless column_exists?(:certification_ship_reviews, :external_certification_id)
      add_column :certification_ship_reviews, :external_certification_id, :string
    end
    add_index :certification_ship_reviews, :external_certification_id, unique: true, algorithm: :concurrently, if_not_exists: true

    safety_assured { remove_index :post_ship_events, :external_certification_id, if_exists: true }
    safety_assured { remove_column :post_ship_events, :external_certification_id, :string, if_exists: true }
  end
end
