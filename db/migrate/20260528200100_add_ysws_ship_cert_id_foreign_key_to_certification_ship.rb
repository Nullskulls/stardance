class AddYswsShipCertIdForeignKeyToCertificationShip < ActiveRecord::Migration[7.2]
  def up
    safety_assured do
      execute "UPDATE certification_ysws_reviews SET ship_cert_id = NULL WHERE ship_cert_id IS NOT NULL"
    end

    add_foreign_key :certification_ysws_reviews, :certification_ship_reviews, column: :ship_cert_id, validate: false
  end

  def down
    remove_foreign_key :certification_ysws_reviews, :certification_ship_reviews
  end
end
