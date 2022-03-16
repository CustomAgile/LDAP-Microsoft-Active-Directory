require 'rubygems'
require 'action_mailer'
require 'rexml/document'
require File.join(File.expand_path(File.dirname(__FILE__)), "encryption/enc_dec")
require File.join(File.expand_path(File.dirname(__FILE__)), "tls_smtp")

class SimpleMailer < ActionMailer::Base
  
  LOG_FILE    = 'logfile_emailer.log'
  
  @logger = Logger.new(LOG_FILE)
  
  def SimpleMailer.send_mail(address, port, user_name, password, recipient, subject, body)
    local_variables.each{ |v| 
      if instance_eval(v).blank? && v != 'msg'
        @logger.warn "Error creating email: argument:#{v} cannot be empty."
        return nil
      end
    }
    
    return nil unless self.validate_email(recipient)
    
    ActionMailer::Base.delivery_method = :smtp
    ActionMailer::Base.smtp_settings = {
      :address          => address,
      :port             => port, 
      :user_name        => user_name,
      :password         => password,
      :authentication   => :plain
    }
    
    begin
      msg = self.create_rally_message(recipient, subject, body)
      self.deliver_rally_message(recipient, subject, body) 
    rescue 
      @logger.error "Error: #{$!} \n 
      Please check your configuration(.xml). You may need to check your email host settings with your System Administrator."
      return nil
    end
    
    return msg
  end
  
  def SimpleMailer.validate_email(recipient)
    begin
      TMail::Address.parse(recipient)
    rescue
      @logger.error $!
      return false
    end
    return true
  end
  
  def rally_message(recipient, subject, body)
    recipients   recipient
    subject      subject
    body         body
  end
end
