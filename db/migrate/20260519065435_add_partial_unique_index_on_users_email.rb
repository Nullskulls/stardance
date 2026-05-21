class AddPartialUniqueIndexOnUsersEmail < ActiveRecord::Migration[8.1]
  disable_ddl_transaction!

  INDEX_NAME = "index_users_on_lower_email_unique".freeze

  def up
    dupes = User.unscoped
                .where.not(email: [ nil, "" ])
                .group("LOWER(email)")
                .having("COUNT(*) > 1")
                .count
    if dupes.any?
      raise "Refusing to add unique index: #{dupes.size} duplicate email group(s) found. " \
            "Sample: #{dupes.first(5).map { |k, v| "#{k}=#{v}" }.join(', ')}"
    end

    return if index_exists?(:users, "LOWER(email)", name: INDEX_NAME)

    add_index :users, "LOWER(email)", unique: true,
              where: "email IS NOT NULL AND email <> ''",
              algorithm: :concurrently,
              name: INDEX_NAME
  end

  def down
    return unless index_exists?(:users, "LOWER(email)", name: INDEX_NAME)

    remove_index :users, name: INDEX_NAME, algorithm: :concurrently
  end
end
