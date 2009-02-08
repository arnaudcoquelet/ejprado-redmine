class CostEntry < ActiveRecord::Base
  # could have used polymorphic association
  # project association here allows easy loading of time entries at project level with one database trip
  belongs_to :project
  belongs_to :issue
  belongs_to :user
  belongs_to :activity, :class_name => 'Enumeration', :foreign_key => :activity_id
  
  attr_protected :project_id, :user_id, :tyear, :tmonth, :tweek

  acts_as_customizable
  acts_as_event :title => Proc.new {|o| "#{o.user}: #{lwr(:label_f_cost, o.costs)} (#{(o.issue || o.project).event_title})"},
                :url => Proc.new {|o| {:controller => 'costlog', :action => 'details', :project_id => o.project}},
                :author => :user,
                :description => :comments
  
  validates_presence_of :user_id, :activity_id, :project_id, :costs, :spent_on
  validates_numericality_of :costs, :allow_nil => true
  validates_length_of :comments, :maximum => 255, :allow_nil => true

  def after_initialize
    if new_record? && self.activity.nil?
      if default_activity = Enumeration.default('ACTI')
        self.activity_id = default_activity.id
      end
    end
  end
  
  def before_validation
    self.project = issue.project if issue && project.nil?
  end
  
  def validate
    errors.add :costs, :activerecord_error_invalid if costs && (costs < 0 || costs >= 10000000)
    errors.add :project_id, :activerecord_error_invalid if project.nil?
    errors.add :issue_id, :activerecord_error_invalid if (issue_id && !issue) || (issue && project!=issue.project)
  end
  
  def costs=(h)
    write_attribute :costs, (h.is_a?(String) ? h.to_hours : h)
  end
  
  def cost=(h)
    write_attribute :costs, (h.is_a?(String) ? h.to_hours : h)
  end
  
  # tyear, tmonth, tweek assigned where setting spent_on attributes
  # these attributes make time aggregations easier
  def spent_on=(date)
    super
    self.tyear = spent_on ? spent_on.year : nil
    self.tmonth = spent_on ? spent_on.month : nil
    self.tweek = spent_on ? Date.civil(spent_on.year, spent_on.month, spent_on.day).cweek : nil
  end
  
  # Returns true if the time entry can be edited by usr, otherwise false
  def editable_by?(usr)
    (usr == user && usr.allowed_to?(:edit_own_cost_entries, project)) || usr.allowed_to?(:edit_cost_entries, project)
  end
  
  def self.visible_by(usr)
    with_scope(:find => { :conditions => Project.allowed_to_condition(usr, :view_cost_entries) }) do
      yield
    end
  end
end
