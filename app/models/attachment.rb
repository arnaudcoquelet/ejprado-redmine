# redMine - project management software
# Copyright (C) 2006-2007  Jean-Philippe Lang
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

require "digest/md5"

class Attachment < ActiveRecord::Base
  belongs_to :container, :polymorphic => true
  belongs_to :author, :class_name => "User", :foreign_key => "author_id"
  
  validates_presence_of :container, :filename, :author
  validates_length_of :filename, :maximum => 255
  validates_length_of :disk_filename, :maximum => 255

  acts_as_event :title => :filename,
                :url => Proc.new {|o| {:controller => 'attachments', :action => 'download', :id => o.id, :filename => o.filename}}

  acts_as_activity_provider :type => 'files',
                            :permission => :view_files,
                            :find_options => {:select => "#{Attachment.table_name}.*", 
                                              :joins => "LEFT JOIN #{Version.table_name} ON #{Attachment.table_name}.container_type='Version' AND #{Version.table_name}.id = #{Attachment.table_name}.container_id " +
                                                        "LEFT JOIN #{Project.table_name} ON #{Version.table_name}.project_id = #{Project.table_name}.id"}
  
  acts_as_activity_provider :type => 'documents',
                            :permission => :view_documents,
                            :find_options => {:select => "#{Attachment.table_name}.*", 
                                              :joins => "LEFT JOIN #{Document.table_name} ON #{Attachment.table_name}.container_type='Document' AND #{Document.table_name}.id = #{Attachment.table_name}.container_id " +
                                                        "LEFT JOIN #{Project.table_name} ON #{Document.table_name}.project_id = #{Project.table_name}.id"}

  cattr_accessor :storage_path
  @@storage_path = "#{RAILS_ROOT}/files"
  
  def validate
    errors.add_to_base :too_long if self.filesize > Setting.attachment_max_size.to_i.kilobytes
  end

  def file=(incoming_file)
    unless incoming_file.nil?
      @temp_file = incoming_file
      if @temp_file.size > 0
        self.filename = sanitize_filename(@temp_file.original_filename)
        self.disk_filename = Attachment.disk_filename(filename)
        self.content_type = @temp_file.content_type.to_s.chomp
        self.filesize = @temp_file.size
      end
    end
  end
	
  def file
    nil
  end

  # Copy temp file to its final location
  def before_save
    if @temp_file && (@temp_file.size > 0)
      logger.debug("saving '#{self.diskfile}'")
      File.open(diskfile, "wb") do |f| 
        f.write(@temp_file.read)
      end
      self.digest = Digest::MD5.hexdigest(File.read(diskfile))
    end
    # Don't save the content type if it's longer than the authorized length
    if self.content_type && self.content_type.length > 255
      self.content_type = nil
    end
  end

  # Deletes file on the disk
  def after_destroy
    File.delete(diskfile) if !filename.blank? && File.exist?(diskfile)
  end

  # Returns file's location on disk
  def diskfile
    "#{@@storage_path}/#{self.disk_filename}"
  end
  
  def increment_download
    increment!(:downloads)
  end

  def project
    container.project
  end
  
  def image?
    self.filename =~ /\.(jpe?g|gif|png)$/i
  end
  
  def is_text?
    Redmine::MimeType.is_type?('text', filename)
  end
  
  def is_diff?
    self.filename =~ /\.(patch|diff)$/i
  end
  
private
  def sanitize_filename(value)
    # get only the filename, not the whole path
    just_filename = value.gsub(/^.*(\\|\/)/, '')
    # NOTE: File.basename doesn't work right with Windows paths on Unix
    # INCORRECT: just_filename = File.basename(value.gsub('\\\\', '/')) 

    # Finally, replace all non alphanumeric, hyphens or periods with underscore
    @filename = just_filename.gsub(/[^\w\.\-]/,'_') 
  end
  
  # Returns an ASCII or hashed filename
  def self.disk_filename(filename)
    df = DateTime.now.strftime("%y%m%d%H%M%S") + "_"
    if filename =~ %r{^[a-zA-Z0-9_\.\-]*$}
      df << filename
    else
      df << Digest::MD5.hexdigest(filename)
      # keep the extension if any
      df << $1 if filename =~ %r{(\.[a-zA-Z0-9]+)$}
    end
    df
  end
end
