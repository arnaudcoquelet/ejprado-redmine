class CostlogController < ApplicationController
  menu_item :issues
  before_filter :find_project, :authorize, :only => [:edit, :destroy]
  before_filter :find_optional_project, :only => [:report, :details]

  verify :method => :post, :only => :destroy, :redirect_to => { :action => :details }
  
  helper :sort
  include SortHelper
  helper :issues
  include CostlogHelper
  helper :custom_fields
  include CustomFieldsHelper

  def report
    @available_criterias = { 'project' => {:sql => "#{CostEntry.table_name}.project_id",
                                          :klass => Project,
                                          :label => :label_project},
                             'version' => {:sql => "#{Issue.table_name}.fixed_version_id",
                                          :klass => Version,
                                          :label => :label_version},
                             'category' => {:sql => "#{Issue.table_name}.category_id",
                                            :klass => IssueCategory,
                                            :label => :field_category},
                             'member' => {:sql => "#{CostEntry.table_name}.user_id",
                                         :klass => User,
                                         :label => :label_member},
                             'tracker' => {:sql => "#{Issue.table_name}.tracker_id",
                                          :klass => Tracker,
                                          :label => :label_tracker},
                             'activity' => {:sql => "#{CostEntry.table_name}.activity_id",
                                           :klass => Enumeration,
                                           :label => :label_activity},
                             'issue' => {:sql => "#{CostEntry.table_name}.issue_id",
                                         :klass => Issue,
                                         :label => :label_issue}
                           }
    
    # Add list and boolean custom fields as available criterias
    custom_fields = (@project.nil? ? IssueCustomField.for_all : @project.all_issue_custom_fields)
    custom_fields.select {|cf| %w(list bool).include? cf.field_format }.each do |cf|
      @available_criterias["cf_#{cf.id}"] = {:sql => "(SELECT c.value FROM #{CustomValue.table_name} c WHERE c.custom_field_id = #{cf.id} AND c.customized_type = 'Issue' AND c.customized_id = #{Issue.table_name}.id)",
                                             :format => cf.field_format,
                                             :label => cf.name}
    end if @project
    
    # Add list and boolean time entry custom fields
    CostEntryCustomField.find(:all).select {|cf| %w(list bool).include? cf.field_format }.each do |cf|
      @available_criterias["cf_#{cf.id}"] = {:sql => "(SELECT c.value FROM #{CustomValue.table_name} c WHERE c.custom_field_id = #{cf.id} AND c.customized_type = 'CostEntry' AND c.customized_id = #{CostEntry.table_name}.id)",
                                             :format => cf.field_format,
                                             :label => cf.name}
    end
    
    @criterias = params[:criterias] || []
    @criterias = @criterias.select{|criteria| @available_criterias.has_key? criteria}
    @criterias.uniq!
    @criterias = @criterias[0,3]
    
    @columns = (params[:columns] && %w(year month week day).include?(params[:columns])) ? params[:columns] : 'month'
    
    retrieve_date_range
    
    unless @criterias.empty?
      sql_select = @criterias.collect{|criteria| @available_criterias[criteria][:sql] + " AS " + criteria}.join(', ')
      sql_group_by = @criterias.collect{|criteria| @available_criterias[criteria][:sql]}.join(', ')
      
      sql = "SELECT #{sql_select}, tyear, tmonth, tweek, spent_on, SUM(costs) AS costs"
      sql << " FROM #{CostEntry.table_name}"
      sql << " LEFT JOIN #{Issue.table_name} ON #{CostEntry.table_name}.issue_id = #{Issue.table_name}.id"
      sql << " LEFT JOIN #{Project.table_name} ON #{CostEntry.table_name}.project_id = #{Project.table_name}.id"
      sql << " WHERE"
      sql << " (%s) AND" % @project.project_condition(Setting.display_subprojects_issues?) if @project
      sql << " (%s) AND" % Project.allowed_to_condition(User.current, :view_cost_entries)
      sql << " (spent_on BETWEEN '%s' AND '%s')" % [ActiveRecord::Base.connection.quoted_date(@from.to_time), ActiveRecord::Base.connection.quoted_date(@to.to_time)]
      sql << " GROUP BY #{sql_group_by}, tyear, tmonth, tweek, spent_on"
      
      @costs = ActiveRecord::Base.connection.select_all(sql)
      
      @costs.each do |row|
        case @columns
        when 'year'
          row['year'] = row['tyear']
        when 'month'
          row['month'] = "#{row['tyear']}-#{row['tmonth']}"
        when 'week'
          row['week'] = "#{row['tyear']}-#{row['tweek']}"
        when 'day'
          row['day'] = "#{row['spent_on']}"
        end
      end
      
      @total_costs = @costs.inject(0) {|s,k| s = s + k['costs'].to_f}
      
      @periods = []
      # Date#at_beginning_of_ not supported in Rails 1.2.x
      date_from = @from.to_time
      # 100 columns max
      while date_from <= @to.to_time && @periods.length < 100
        case @columns
        when 'year'
          @periods << "#{date_from.year}"
          date_from = (date_from + 1.year).at_beginning_of_year
        when 'month'
          @periods << "#{date_from.year}-#{date_from.month}"
          date_from = (date_from + 1.month).at_beginning_of_month
        when 'week'
          @periods << "#{date_from.year}-#{date_from.to_date.cweek}"
          date_from = (date_from + 7.day).at_beginning_of_week
        when 'day'
          @periods << "#{date_from.to_date}"
          date_from = date_from + 1.day
        end
      end
    end
    
    respond_to do |format|
      format.html { render :layout => !request.xhr? }
      format.csv  { send_data(report_to_csv(@criterias, @periods, @costs).read, :type => 'text/csv; header=present', :filename => 'costlog.csv') }
    end
  end
  
  def details
    sort_init 'spent_on', 'desc'
    sort_update
    
    cond = ARCondition.new
    if @project.nil?
      cond << Project.allowed_to_condition(User.current, :view_cost_entries)
    elsif @issue.nil?
      cond << @project.project_condition(Setting.display_subprojects_issues?)
    else
      cond << ["#{CostEntry.table_name}.issue_id = ?", @issue.id]
    end
    
    retrieve_date_range
    cond << ['spent_on BETWEEN ? AND ?', @from, @to]

    CostEntry.visible_by(User.current) do
      respond_to do |format|
        format.html {
          # Paginate results
          @entry_count = CostEntry.count(:include => :project, :conditions => cond.conditions)
          @entry_pages = Paginator.new self, @entry_count, per_page_option, params['page']
          @entries = CostEntry.find(:all, 
                                    :include => [:project, :activity, :user, {:issue => :tracker}],
                                    :conditions => cond.conditions,
                                    :order => sort_clause,
                                    :limit  =>  @entry_pages.items_per_page,
                                    :offset =>  @entry_pages.current.offset)
          @total_costs = CostEntry.sum(:costs, :include => :project, :conditions => cond.conditions).to_f

          render :layout => !request.xhr?
        }
        format.atom {
          entries = CostEntry.find(:all,
                                   :include => [:project, :activity, :user, {:issue => :tracker}],
                                   :conditions => cond.conditions,
                                   :order => "#{CostEntry.table_name}.created_on DESC",
                                   :limit => Setting.feeds_limit.to_i)
          render_feed(entries, :title => l(:label_spent_cost))
        }
        format.csv {
          # Export all entries
          @entries = CostEntry.find(:all, 
                                    :include => [:project, :activity, :user, {:issue => [:tracker, :assigned_to, :priority]}],
                                    :conditions => cond.conditions,
                                    :order => sort_clause)
          send_data(entries_to_csv(@entries).read, :type => 'text/csv; header=present', :filename => 'costlog.csv')
        }
      end
    end
  end
  
  def edit
    render_403 and return if @cost_entry && !@cost_entry.editable_by?(User.current)
    @cost_entry ||= CostEntry.new(:project => @project, :issue => @issue, :user => User.current, :spent_on => Date.today)
    @cost_entry.attributes = params[:cost_entry]
    if request.post? and @cost_entry.save
      flash[:notice] = l(:notice_successful_update)
      redirect_back_or_default :action => 'details', :project_id => @cost_entry.project
      return
    end    
  end
  
  def destroy
    render_404 and return unless @cost_entry
    render_403 and return unless @cost_entry.editable_by?(User.current)
    @cost_entry.destroy
    flash[:notice] = l(:notice_successful_delete)
    redirect_to :back
  rescue ::ActionController::RedirectBackError
    redirect_to :action => 'details', :project_id => @cost_entry.project
  end

private
  def find_project
    if params[:id]
      @cost_entry = CostEntry.find(params[:id])
      @project = @cost_entry.project
    elsif params[:issue_id]
      @issue = Issue.find(params[:issue_id])
      @project = @issue.project
    elsif params[:project_id]
      @project = Project.find(params[:project_id])
    else
      render_404
      return false
    end
  rescue ActiveRecord::RecordNotFound
    render_404
  end
  
  def find_optional_project
    if !params[:issue_id].blank?
      @issue = Issue.find(params[:issue_id])
      @project = @issue.project
    elsif !params[:project_id].blank?
      @project = Project.find(params[:project_id])
    end
    deny_access unless User.current.allowed_to?(:view_cost_entries, @project, :global => true)
  end
  
  # Retrieves the date range based on predefined ranges or specific from/to param dates
  def retrieve_date_range
    @free_period = false
    @from, @to = nil, nil

    if params[:period_type] == '1' || (params[:period_type].nil? && !params[:period].nil?)
      case params[:period].to_s
      when 'today'
        @from = @to = Date.today
      when 'yesterday'
        @from = @to = Date.today - 1
      when 'current_week'
        @from = Date.today - (Date.today.cwday - 1)%7
        @to = @from + 6
      when 'last_week'
        @from = Date.today - 7 - (Date.today.cwday - 1)%7
        @to = @from + 6
      when '7_days'
        @from = Date.today - 7
        @to = Date.today
      when 'current_month'
        @from = Date.civil(Date.today.year, Date.today.month, 1)
        @to = (@from >> 1) - 1
      when 'last_month'
        @from = Date.civil(Date.today.year, Date.today.month, 1) << 1
        @to = (@from >> 1) - 1
      when '30_days'
        @from = Date.today - 30
        @to = Date.today
      when 'current_year'
        @from = Date.civil(Date.today.year, 1, 1)
        @to = Date.civil(Date.today.year, 12, 31)
      end
    elsif params[:period_type] == '2' || (params[:period_type].nil? && (!params[:from].nil? || !params[:to].nil?))
      begin; @from = params[:from].to_s.to_date unless params[:from].blank?; rescue; end
      begin; @to = params[:to].to_s.to_date unless params[:to].blank?; rescue; end
      @free_period = true
    else
      # default
    end
    
    @from, @to = @to, @from if @from && @to && @from > @to
    @from ||= (CostEntry.minimum(:spent_on, :include => :project, :conditions => Project.allowed_to_condition(User.current, :view_cost_entries)) || Date.today) - 1
    @to   ||= (CostEntry.maximum(:spent_on, :include => :project, :conditions => Project.allowed_to_condition(User.current, :view_cost_entries)) || Date.today)
  end
end