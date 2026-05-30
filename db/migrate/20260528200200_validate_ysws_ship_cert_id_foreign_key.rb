class ValidateYswsShipCertIdForeignKey < ActiveRecord::Migration[7.2]
  def up
    validate_foreign_key :certification_ysws_reviews, :certification_ship_reviews
  end

  def down
  end
end
