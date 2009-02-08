class Notifier < ActionMailer::Base

  helper :application
  include ApplicationHelper
  helper :projects
  include ProjectsHelper
  helper :ifpdf
  include IfpdfHelper
  include IssuesHelper

  def project_information(project, issues)
    headers 'X-Mailer' => 'Redmine',
      'X-Redmine-Host' => Setting.host_name,
      'X-Redmine-Site' => Setting.app_title
    recipients project.email
    from       Setting.mail_from
    subject    "Informacion del proyecto " + project.name
    body       :project => project,
      :issues => issues
  end

  def project_pdf(project, issues, pdf)
    headers 'X-Mailer' => 'Redmine',
            'X-Redmine-Host' => Setting.host_name,
            'X-Redmine-Site' => Setting.app_title
    recipients project.email
    from       Setting.mail_from
    subject    "Informacion del proyecto " + project.name
    body       :project => project,
               :issues => issues

    attachment :content_type => "application/pdf", :filename => project.name + '-' + Date.today.to_s + '.pdf' do |a|
      a.body = pdf
    end

  end


  # Overrides default deliver! method to prevent from sending an email
  # with no recipient, cc or bcc
  def deliver!(mail = @mail)
    return false if (recipients.nil? || recipients.empty?) &&
      (cc.nil? || cc.empty?) &&
      (bcc.nil? || bcc.empty?)
    super
  end

end
