class AddExternalCertificationIdToPostShipEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :post_ship_events, :external_certification_id, :string
    add_index :post_ship_events, :external_certification_id, unique: true
  end
end
