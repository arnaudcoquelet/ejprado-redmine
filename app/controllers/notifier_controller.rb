# redMine - project management software
# Copyright (C) 2006-2008  Jean-Philippe Lang
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
# 
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
# 
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.

class NotifierController < ActionController::Base

  helper :journals
  helper :projects
  include ProjectsHelper
  helper :custom_fields
  include CustomFieldsHelper
  helper :ifpdf
  include IfpdfHelper
  helper :issue_relations
  include IssueRelationsHelper
  helper :watchers
  include WatchersHelper
  helper :attachments
  include AttachmentsHelper
  helper :queries
  helper :sort
  include SortHelper
  include IssuesHelper
  helper :timelog
  helper :costlog

  # Submits an incoming email to MailHandler
  def index
    options = params.dup
    email = options.delete(:email)
    if MailHandler.receive(email, options)
      render :nothing => true, :status => :created
    else
      render :nothing => true, :status => :unprocessable_entity
    end
  end

  def generate_pdf(project)
    pdf=IfpdfHelper::IFPDF.new(current_language)
    title = project ? "#{project.name} - #{l(:label_issue_plural)}" : "#{l(:label_issue_plural)}"
    title = "TEST"
    pdf.SetTitle(title)
    pdf.AliasNbPages
    pdf.footer_date = format_date(Date.today)
    pdf.AddPage("L")
    row_height = 7
	
    #
    # title
    #
    pdf.SetFontStyle('B',11)   	
   	pdf.Cell(190,10, title)
    pdf.Ln
	
    #
    # headers
    #	
    pdf.SetFontStyle('B',10)
    pdf.SetFillColor(230, 230, 230)
   	pdf.Cell(15, row_height, "#", 0, 0, 'L', 1)
   	pdf.Cell(30, row_height, l(:field_tracker), 0, 0, 'L', 1)
	  pdf.Cell(25, row_height, l(:field_client_buyer_name), 0, 0, 'L', 1)
	  pdf.Cell(30, row_height, l(:field_client_buyer_firstname), 0, 0, 'L', 1)
  	pdf.Cell(20, row_height, l(:field_client_buyer_idnumber), 0, 0, 'L', 1)
   	pdf.Cell(70, row_height, l(:field_subject), 0, 0, 'L', 1)
   	pdf.Cell(30, row_height, l(:field_status), 0, 0, 'L', 1)
   	pdf.Cell(20, row_height, l(:field_start_date), 0, 0, 'L', 1)
   	pdf.Cell(20, row_height, l(:field_due_date), 0, 0, 'L', 1)
    pdf.Cell(20, row_height, l(:field_done_ratio), 0, 0, 'L', 1)
   	pdf.Line(10, pdf.GetY, 290, pdf.GetY)
   	pdf.Ln
   	pdf.Line(10, pdf.GetY, 290, pdf.GetY)
   	pdf.SetY(pdf.GetY() + 1)
	
    #
    # rows
    #
    pdf.SetFontStyle('',9)
    pdf.SetFillColor(255, 255, 255)
    issues = project.issues.all
    issues.each do |issue|
      pdf.Cell(15, row_height, issue.id.to_s, 0, 0, 'L', 1)
	   	pdf.Cell(30, row_height, issue.tracker.name, 0, 0, 'L', 1)
      pdf.Cell(25, row_height, issue.client_buyer_name, 0, 0, 'L', 1)
      pdf.Cell(30, row_height, issue.client_buyer_firstname, 0, 0, 'L', 1)
      pdf.Cell(20, row_height, issue.client_buyer_idnumber, 0, 0, 'L', 1)
      pdf.Cell(70, row_height, issue.subject, 0, 0, 'L', 1)
	   	pdf.Cell(30, row_height, issue.status.name, 0, 0, 'L', 1)
	   	pdf.Cell(20, row_height, format_date(issue.start_date), 0, 0, 'L', 1)
	   	pdf.Cell(20, row_height, format_date(issue.due_date), 0, 0, 'L', 1)
	   	pdf.Cell(20, row_height, issue.done_ratio.to_s + ' %', 0, 0, 'R', 1)
      pdf.MultiCell(0, row_height, "")
      pdf.Line(10, pdf.GetY, 290, pdf.GetY)
      pdf.SetY(pdf.GetY() + 1)
    end
    
    return pdf
  end

  def send_project_information_email_pdf
    # triggered via:
    # http://localhost:3000/notifier/send_project_information_email_pdf

    # note the deliver_ prefix, this is IMPORTANT    
    projects = Project.all
    projects.each do |project|        
      pdf = generate_pdf(project)
      Notifier.deliver_project_pdf(project, project.issues.all, pdf.Output)
    end
    # render the default action
    redirect_to :controller => 'welcome'
  end

  def send_project_information_email_html
    # triggered via:
    # http://localhost:3000/notifier/send_project_information_email_html

    # note the deliver_ prefix, this is IMPORTANT
    projects = Project.all
    projects.each do |project|
      Notifier.deliver_project_information(project, project.issues.all)
    end
    # render the default action
    # Redirect to Projects/Index.html
    redirect_to :controller => 'welcome'
  end

  def update_issues_gravity
    # triggered via:
    # http://localhost:3000/notifier/update_issues_gravity
    # Update all issues gravity
    projects = Project.all
    projects.each do |project|
      issues = project.issues.all
      issues.each do |issue|
        issue.set_qualification()
      end
    end
    # render the default action
    # Redirect to Projects/Index.html
    #redirect_to :controller => 'projects', :action => 'index'
    redirect_to :controller => 'welcome'
  end


end
