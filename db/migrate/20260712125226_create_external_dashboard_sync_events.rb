class CreateExternalDashboardSyncEvents < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def change
    create_table :external_dashboard_sync_events do |t|
      t.bigint :cert_id, null: false
      t.integer :outcome, null: false
      t.text :message
      t.string :run_id

      t.timestamps
    end
    add_index :external_dashboard_sync_events, :cert_id
    add_index :external_dashboard_sync_events, :run_id
    add_foreign_key :external_dashboard_sync_events, :certification_ship_reviews,
                    column: :cert_id, on_delete: :cascade, validate: false
    validate_foreign_key :external_dashboard_sync_events, :certification_ship_reviews
  end
end
