class CreateCostEntries < ActiveRecord::Migration
  def self.up
    create_table :cost_entries do |t|
      t.integer :project_id
      t.integer :user_id
      t.integer :issue_id
      t.float :costs
      t.string :comments
      t.integer :activity_id
      t.date :spent_on
      t.integer :tyear
      t.integer :tmonth
      t.integer :tweek
	  
      t.timestamps
    end
	add_index :cost_entries, [:project_id], :name => :cost_entries_project_id
    add_index :cost_entries, [:issue_id], :name => :cost_entries_issue_id
  end

  def self.down
    drop_table :cost_entries
  end
end
