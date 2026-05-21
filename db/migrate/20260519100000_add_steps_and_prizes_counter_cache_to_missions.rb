class AddStepsAndPrizesCounterCacheToMissions < ActiveRecord::Migration[8.0]
  def up
    add_column :missions, :steps_count, :integer, default: 0, null: false
    add_column :missions, :prizes_count, :integer, default: 0, null: false

    Mission.unscoped.find_each do |mission|
      Mission.reset_counters(mission.id, :steps, :prizes)
    end
  end

  def down
    remove_column :missions, :prizes_count
    remove_column :missions, :steps_count
  end
end
