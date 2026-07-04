class AddProofVideoUrlToCertificationShipReviews < ActiveRecord::Migration[8.1]
  def change
    add_column :certification_ship_reviews, :proof_video_url, :string
  end
end
