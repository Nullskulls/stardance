class DropFunnelEvents < ActiveRecord::Migration[8.1]
  def change
    drop_table :funnel_events do |t|
      t.string :event_name, null: false
      t.bigint :user_id
      t.string :email
      t.jsonb :properties, default: {}, null: false

      t.timestamps null: false

      t.index :created_at
      t.index :email
      t.index [ :event_name, :created_at ]
      t.index :event_name
      t.index :user_id
    end
  end
end
