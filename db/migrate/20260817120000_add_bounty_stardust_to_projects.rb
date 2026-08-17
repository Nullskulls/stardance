class AddBountyStardustToProjects < ActiveRecord::Migration[8.1]
  def change
    add_column :projects, :bounty_stardust, :integer
    add_column :projects, :bounty_paid_at, :datetime
  end
end
