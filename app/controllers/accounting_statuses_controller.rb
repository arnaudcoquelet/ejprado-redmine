# redMine - project management software
# Copyright (C) 2006  Jean-Philippe Lang
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

class AccountingStatusesController < ApplicationController
  before_filter :require_admin

  verify :method => :post, :only => [ :destroy, :create, :update, :move ],
         :redirect_to => { :action => :list }
         
  def index
    list
    render :action => 'list' unless request.xhr?
  end

  def list
    @accounting_status_pages, @accounting_statuses = paginate :accounting_statuses, :per_page => 25, :order => "position"
    render :action => "list", :layout => false if request.xhr?
  end

  def new
    @accouting_status = AccountingStatus.new
  end

  def create
    @accounting_status = AccountingStatus.new(params[:accounting_status])
    if @accounting_status.save
      flash[:notice] = l(:notice_successful_create)
      redirect_to :action => 'list'
    else
      render :action => 'new'
    end
  end

  def edit
    @accounting_status = AccountingStatus.find(params[:id])
  end

  def update
    @accounting_status = AccountingStatus.find(params[:id])
    if @accounting_status.update_attributes(params[:accounting_status])
      flash[:notice] = l(:notice_successful_update)
      redirect_to :action => 'list'
    else
      render :action => 'edit'
    end
  end
  
  def move
    @accounting_status = AccountingStatus.find(params[:id])
    case params[:position]
    when 'highest'
      @issue_status.move_to_top
    when 'higher'
      @issue_status.move_higher
    when 'lower'
      @issue_status.move_lower
    when 'lowest'
      @issue_status.move_to_bottom
    end if params[:position]
    redirect_to :action => 'list'
  end

  def destroy
    AccountingStatus.find(params[:id]).destroy
    redirect_to :action => 'list'
  rescue
    flash[:error] = "Unable to delete issue status"
    redirect_to :action => 'list'
  end  	
end
