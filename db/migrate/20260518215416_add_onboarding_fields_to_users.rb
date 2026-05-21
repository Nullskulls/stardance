class AddOnboardingFieldsToUsers < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  def up
    add_column :users, :age_attestation, :string  unless column_exists?(:users, :age_attestation)
    add_column :users, :experience_level, :string unless column_exists?(:users, :experience_level)
    add_column :users, :interests, :string, array: true, default: [] unless column_exists?(:users, :interests)
    add_column :users, :onboarded_at, :datetime unless column_exists?(:users, :onboarded_at)

    unless index_exists?(:users, :onboarded_at)
      add_index :users, :onboarded_at, algorithm: :concurrently
    end

    User.where(onboarded_at: nil).in_batches(of: 1_000).update_all(onboarded_at: Time.current)
  end

  def down
    remove_index  :users, :onboarded_at if index_exists?(:users, :onboarded_at)
    remove_column :users, :onboarded_at
    remove_column :users, :interests
    remove_column :users, :experience_level
    remove_column :users, :age_attestation
  end
end
