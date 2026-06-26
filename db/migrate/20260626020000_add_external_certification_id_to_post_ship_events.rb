class AddExternalCertificationIdToPostShipEvents < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    add_column :post_ship_events, :external_certification_id, :string unless column_exists?(:post_ship_events, :external_certification_id)
    add_index :post_ship_events, :external_certification_id, unique: true, algorithm: :concurrently, if_not_exists: true
  end
end
