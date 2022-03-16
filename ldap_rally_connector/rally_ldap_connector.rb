require 'rubygems'
require 'net/ldap'
require 'rally_rest_api'
require 'rexml/document'
require 'time'
require File.join(File.expand_path(File.dirname(__FILE__)), "encryption/enc_dec")
require File.join(File.expand_path(File.dirname(__FILE__)), "connection_helper")
require File.join(File.expand_path(File.dirname(__FILE__)), "user_helper/user_helper")
require File.join(File.expand_path(File.dirname(__FILE__)), "simple_mailer")

class RallyLdapConnector
  
  attr_reader :attr_hash
  
  INTEGRATION_VERSION = '1.0'
  API_VERSION = '1.08'
  LOG_FILE_NAME = 'logfile.log'
  RALLY_LOGIN_REGEXP = /[a-zA-Z0-9\.\-\_\']+\@[a-zA-Z0-9\.\-\_\']+\.[a-zA-Z]+/  
  REQUIRED_TAGS = Array[ "RallyServerURL", "RallyUserName", 
    "RallyPassword", "RallyEncryptedPassword", "LdapHost", "LdapEncryptedPassword",
    "LdapPort", "LdapTreeBase", "LdapRallyAttr", "LdapRallyValue", "LdapInactiveAttr",
    "LdapInactiveValue", "RallyLoginName", "RallyEmailAddress", "RallyFirstName",
    "RallyLastName", "RallyDisplayName", "RunInterval", "ServicePriority", "EmailEnabled",
    "EmailServerHost", "EmailServerPort", "EmailAccountUserName", "EmailAccountEncryptedPassword",
    "SendEmailTo"]
  DEFAULT_PERMISSION = "User"
  
  #TODO: make constants for hash keys, etc.
  
  def initialize(config_file)
    @config_file = config_file
    @logger = LogWrapper.new(LOG_FILE_NAME)
    @logger.level = Logger::INFO   
    @logger.info "***************************************" 
    @logger.info "Rally-LDAP connector version #{INTEGRATION_VERSION} started"
    @ok_to_run = read_config(@config_file) && rally_loginname_setup?
    exit if !@ok_to_run     
    @last_run = DateTime.new
    @connection_helper = ConnectionHelper.new(@logger)
    @user_helper = nil
  end
  
  def run()
    rally_ok = connect_to_rally() 
    ldap_ok = connect_to_ldap()   
    
    if (ldap_ok && !rally_ok.nil?)
      services = @services_to_run.split(',')     
      loop do      
        run_services()     
        sleep(60*@run_interval.to_f)      
      end      
    end    
  end
  
  def run_services
    created_users = Array.new 
    disabled_users = Array.new
    services = @services_to_run.split(',')
    services.each do |service_num| 
      update = nil
      case service_num
        when '1' 
          @logger.info "************Service 1*****************"
          update = provision_users(true) if ldap_rally_filter_setup(service_num)
          created_users = update unless update.nil?          
        when '1p'
          @logger.info "*******PREVIEW MODE: Service 1p*******"
          provision_users(false) if ldap_rally_filter_setup(service_num) 
        when '2'
          @logger.info "************Service 2*****************"
          update = disable_users(true) if ldap_inactive_filter_setup(service_num)
          disabled_users = update unless update.nil?          
        when '2p'
          @logger.info "*******PREVIEW MODE: Service 2p*******" 
          disable_users(false) if ldap_inactive_filter_setup(service_num)
      end
    end

    email_results(created_users, disabled_users) if @email_enable == 'true'
  end
  
  def email_results(created_users, disabled_users)
    return if created_users.empty? && disabled_users.empty?
    subject = 'Ldap -> Rally User Updates'
    body = ''
    unless created_users.empty?
      body += "The following users were found in LDAP and have been created in Rally:\n"
      created_users.each{|cu| body += "#{cu.login_name} \n"}
      body += "\n\n"
    end
    unless disabled_users.empty?
      body += "The following users are disabled in LDAP and have been disabled in Rally:\n"
      disabled_users.each{|du| body += "#{du.login_name} \n"}
      body += "\n\n"
    end
    
    mail_sent = SimpleMailer.send_mail(@email_server_host, @email_server_port, @email_account_username, 
      @email_account_encrypted_password, @send_mail_to, subject, body)
    @logger.info "Email notification successfully sent to #{@send_mail_to}" if !mail_sent.nil?
    @logger.info "Email notification unsuccessful.  Check logfile_emailer.log for details" if mail_sent.nil?
  end
  
  def terminate
    @logger.close() unless @logger.nil?
  end
  
  def connect_to_rally()
    rally_fields = {
      :base_url => @rally_url,
      :username => @rally_user,
      :password => @rally_password,
      :version => API_VERSION }
    
    begin
      @rally = @connection_helper.connect_to_rally(rally_fields)
      return @rally
    rescue
      @logger.error "#{$!}"
      @logger.error "Could not connect to Rally: #{default_connection[:base_url]}"      
      return nil
    end    
    
  end
  
  #TODO: can net::ldap accept a single hash?
  def connect_to_ldap
    begin
      @ldap = Net::LDAP.new(:host => @ldap_host,
                            :port => @ldap_port,
                            :auth => { :method => :simple,
        :username => @ldap_username,
        :password => @ldap_password } )
      @logger.info "Connecting to LDAP: '#{@ldap_host}' on port #{@ldap_port}"
      @logger.info "Binding to LDAP as: #{@ldap_username}"
      
      success = @ldap.bind()
      if (success)
        @logger.info "LDAP authorization succeeded"
        return true
      else
        @logger.error "LDAP authorization failed: #{@ldap.get_operation_result.message}"
        return false
      end
    rescue Net::LDAP::LdapError => error
      @logger.error("Error connecting to LDAP: #{error}")
      return false
    end
  end
  
  def provision_users(create_flag)
    @logger.info "Starting Service 1p in PREVIEW mode to provision users in Rally..." if !create_flag
    @logger.info "No users in Rally will actually be created!" if !create_flag
    @logger.info "Starting Service 1 to provision users in Rally..." if create_flag
    @logger.info "Creating Rally users that match LDAP user filter of"
    @logger.info "   #{@ldap_rally_attr}=#{@ldap_rally_value}"
    @logger.info "with Rally fields mapped as follows:"
    @logger.info "   Rally login name      #{@attr_hash[:login_name]}"
    @logger.info "   Rally email address   #{@attr_hash[:email_address]}" if !@attr_hash[:email_address].nil?
    @logger.info "   Rally first name      #{@attr_hash[:first_name]}" if !@attr_hash[:first_name].nil?
    @logger.info "   Rally last name       #{@attr_hash[:last_name]}" if !@attr_hash[:last_name].nil?
    @logger.info "   Rally display name    #{@attr_hash[:display_name]}" if !@attr_hash[:display_name].nil?
    
    @user_helper = get_user_helper(create_flag)
    
    ldap_entries = get_ldap_entries()          
    check_ldap_entries_returned(ldap_entries)  
    
    created_users = Array.new
    begin
      ldap_entries.each do |entry| 
        rally_user = @user_helper.find_user(entry[@attr_hash[:login_name]][0].downcase)
        if rally_user.nil?
          successfully_created_ldap_user = create_rally_user(entry)
          #TODO before Beta, probably can remove this before sending to customers        
          rally_modified_flag = true if !successfully_created_ldap_user.nil?
          created_users << successfully_created_ldap_user if !successfully_created_ldap_user.nil?
        end
      end

    rescue Net::LDAP::LdapError => error
      @logger.error("LDAP error: #{error}")
      return nil
    end 
    
    if created_users.empty?
      @logger.info "No new LDAP user(s) to provision in Rally"  
      return nil 
    end    
    
    return created_users
  end
  
  def disable_users(create_flag)
    @logger.info "Starting Service 2p in PREVIEW mode to enable/disable users in Rally..." if !create_flag
    @logger.info "No users in Rally will actually be disabled/enabled in Rally!" if !create_flag
    @logger.info "Starting Service 2 to enable/disable users in Rally..." if create_flag
    @logger.info "Disabling Rally users that match LDAP filter of"
    @logger.info "   #{@ldap_inactive_attr}=#{@ldap_inactive_value}"  
    
    @user_helper = get_user_helper(create_flag)
    
    disabled_entries =  get_disabled_rally_users()        
    check_ldap_entries_returned(disabled_entries)
    
    disabled_users = Array.new
    begin
      disabled_entries.each do |entry|
      rally_user = @user_helper.find_user(entry[@attr_hash[:login_name]][0].downcase)  
      if !rally_user.nil? && @attr_hash.has_key?(:disabled) then      
        if entry[@attr_hash[:disabled]][0] != @ldap_inactive_value && rally_user.disabled == 'true' then
          @user_helper.enable_user(rally_user)
        end   
        if entry[@attr_hash[:disabled]][0] == @ldap_inactive_value && rally_user.disabled == 'false' then
          @user_helper.disable_user(rally_user)
          disabled_users << rally_user unless !create_flag
        end                 
      end   
    end
    rescue Net::LDAP::LdapError => error
      @logger.error("LDAP error: #{error}")
      return nil
    end
  
    if disabled_users.empty?
      @logger.info "No LDAP user(s) to enable/disable in Rally"
      return nil
    end
    
    return disabled_users
  end
  
  def create_rally_user(ldap_user)
    begin
      created_user = @user_helper.create_user_with_hash(get_fields(ldap_user))
      set_user_permissions(created_user) unless created_user.nil?      
    rescue
      @logger.error("Unable to create user #{ldap_user[@attr_hash[:login_name]][0]}")
      return nil
    end
    return created_user   
  end
  
  def get_disabled_rally_users()
    rally_filter = Net::LDAP::Filter.eq( @ldap_rally_attr, @ldap_rally_value ) 
    #& Net::LDAP::Filter.eq( @ldap_inactive_attr, @ldap_inactive_value)
    list = Array.new
    
    begin
      result_set = @ldap.search(:base => @ldap_tree_base, :filter => rally_filter,
                                :attributes => @attrs, :return_result => false) do |entry|   
        list << entry if valid_entry?(entry)
      end
    rescue Net::LDAP::LdapError => error
      @logger.error("LDAP error: #{error}")
      nil
    end
    
    list    
  end
  
  def get_user_helper(create_flag)
    @user_helper = UserHelper.new(@rally, @logger, create_flag )
  end
  
  def read_config(config_file)
    file = File.new(config_file)
    begin
      doc = REXML::Document.new file
      validate_config(doc)
      
      @rally_url      = doc.root.elements['RallyServerURL'].text
      @rally_user     = doc.root.elements['RallyUserName'].text
     
      # if RallyPassword is empty, OR if both are populated, use Encrypted version
      if (doc.root.elements['RallyPassword'].text == nil) or 
       (doc.root.elements['RallyPassword'].text != nil &&
        doc.root.elements['RallyEncryptedPassword'].text != nil)
        begin
          @rally_password = EncDec.decrypt_from_ascii(doc.root.elements['RallyEncryptedPassword'].text)
        rescue
          # call to EncDec::encrypt can raise 'bad decrypt' exception
          # catch it, log it, inform the user and exit
          error_msg = "ERROR: Decryption process raised exception: #{$!}. \n"
          error_msg += "Probable cause is RallyEncryptedPassword element in config file has been changed.\n"
          error_msg += "Please re-run encryption/configure_credentials.rb\n\n"
          @logger.error error_msg
          puts error_msg
          raise StandardError
        end
      else
        @rally_password = doc.root.elements['RallyPassword'].text
      end
      
      if (doc.root.elements['RallyPassword'].text != nil && 
        doc.root.elements['RallyEncryptedPassword'].text != nil)
        @logger.warn "Both encrypted and non encrypted passwords exist for Rally, please remove one."
      end
      
      @ldap_tree_base = doc.root.elements['LdapTreeBase'].text
      @ldap_host = doc.root.elements['LdapHost'].text
      @ldap_port = doc.root.elements['LdapPort'].text
      @ldap_username = doc.root.elements['LdapUserName'].text
      
      # if LdapPassword is empty, OR if both are populated, use Encrypted version
      if (doc.root.elements['LdapPassword'].text == nil) or 
       (doc.root.elements['LdapPassword'].text != nil &&
        doc.root.elements['LdapEncryptedPassword'].text != nil)
        begin
          @ldap_password = EncDec.decrypt_from_ascii(doc.root.elements['LdapEncryptedPassword'].text)
        rescue
          # call to EncDec::encrypt can raise 'bad decrypt' exception
          # catch it, log it, inform the user and exit
          error_msg = "ERROR: Decryption process raised exception: #{$!}. \n"
          error_msg += "Probable cause is LdapEncryptedPassword element in config file has been changed.\n"
          error_msg += "Please re-run encryption/configure_credentials.rb\n\n"
          @logger.error error_msg
          puts error_msg
          raise StandardError
        end
      else
        @ldap_password = doc.root.elements['LdapPassword'].text
      end
      
      if (doc.root.elements['LdapPassword'].text != nil &&
        doc.root.elements['LdapEncryptedPassword'].text != nil)
        @logger.warn "Both encrypted and non encrypted passwords exist for LDAP, please remove one."
      end
      
      @ldap_rally_attr = doc.root.elements['LdapRallyAttr'].text
      @ldap_rally_value = doc.root.elements['LdapRallyValue'].text
      @ldap_inactive_attr = doc.root.elements['LdapInactiveAttr'].text
      @ldap_inactive_value = doc.root.elements['LdapInactiveValue'].text
      
      @rally_login_name_attr = doc.root.elements['RallyLoginName'].text
      @rally_first_name_attr = doc.root.elements['RallyFirstName'].text
      @rally_last_name_attr = doc.root.elements['RallyLastName'].text
      @rally_email_attr = doc.root.elements['RallyEmailAddress'].text
      @rally_display_name_attr = doc.root.elements['RallyDisplayName'].text
      
      @email_enable = doc.root.elements['EmailEnabled'].text
      @email_server_host = doc.root.elements['EmailServerHost'].text
      @email_server_port = doc.root.elements['EmailServerPort'].text
      @email_account_username = doc.root.elements['EmailAccountUserName'].text
      @send_mail_to = doc.root.elements['SendEmailTo'].text
      
      # email_account_encrypted_password does not have a plain-text equivalent,
      # so no check for the plain-text tag is needed
      begin
        @email_account_encrypted_password = EncDec.decrypt_from_ascii(doc.root.elements['EmailAccountEncryptedPassword'].text) if @email_enable == 'true'
      rescue
        # call to EncDec::encrypt can raise 'bad decrypt' exception
        # catch it, log it, inform the user and exit
        error_msg = "ERROR: Decryption process raised exception: #{$!}. \n"
        error_msg += "Probable cause is EmailAccountEncryptedPassword element in config file has been changed.\n"
        error_msg += "Please re-run encryption/configure_credentials.rb\n\n"
        @logger.error error_msg
        puts error_msg
        raise StandardError
      end
      
      @run_interval = doc.root.elements['RunInterval'].text
      @services_to_run = doc.root.elements['ServicePriority'].text
      
      create_attr_array()
      succeed = true   
      
    rescue REXML::ParseException => ex
      error_msg = "Invalid configuration file (#{config_file}) - #{ex.continued_exception}"    
      log_fatal_error(error_msg)
      succeed =  false
      raise
      
    rescue Errno::ENOENT => ex
      error_msg = "#{ex.message}"
      log_fatal_error(error_msg)
      succeed =  false
      raise
      
    rescue => ex
      error_msg = "Invalid configuration file (#{config_file}) - #{ex.message}"
      log_fatal_error(error_msg)
      succeed =  false
      raise
      
    ensure
      file.close() unless file.nil?
    end
    
    return succeed
  end
  
  def get_ldap_entries()  
    
    rally_filter = Net::LDAP::Filter.eq( @ldap_rally_attr, @ldap_rally_value )   
    list = Array.new
    
    begin
      @ldap.auth(@ldap_username, @ldap_password)
      result_set = @ldap.search(:base => @ldap_tree_base, :filter => rally_filter, 
                                :attributes => @attrs, :return_result => false) do |entry|                        
        list << entry if valid_entry?(entry) && !is_disabled?(entry)
      end
    rescue Net::LDAP::LdapError => error
      @logger.error("Error connecting to LDAP server: #{error}")
      nil
    end
    list
  end  
  
  
  #--------- Private methods --------------
  private
  
  def validate_config(doc)
    REQUIRED_TAGS.each do |tag_name|
      raise MissingTagError, "#{tag_name} tag is missing" if doc.root.elements[tag_name].nil?
    end
  end
  
  def ldap_inactive_filter_setup(service_num) 
    if !@ldap_inactive_attr.nil? && !@ldap_inactive_attr.nil? then
      return true
    else
      @logger.error "Cannot execute Service #{service_num}..." 
      @logger.error "LdapInactiveAttr and/or LdapInactiveValue are blank in config file"   
      return false
    end
  end
  
  def rally_loginname_setup?
    if !@rally_login_name_attr.nil? then
      return true
    else     
      @logger.error "RallyLoginName must have a value in config file!"
      return false
    end
  end
  
  def ldap_rally_filter_setup(service_num)
    if !@ldap_rally_attr.nil? && !@ldap_rally_attr.nil? then
      return true
    else
      @logger.error "Cannot execute Service #{service_num}..."
      @logger.error "LdapRallyAttr and/or LdapRallyValue are blank in config file"   
      return false
    end
  end
  
  def check_ldap_entries_returned(entries)   
    if entries.length == 0
      @logger.info "No LDAP users returned from query"
      nil
    else
      @logger.info "LDAP search returned '#{entries.length}' entries"
      true
    end
  end
  
  def create_attr_array()
    @attr_hash = Hash.new
    @attr_hash[:login_name] = @rally_login_name_attr
    
    if !@rally_email_attr.nil? && @rally_email_attr.length > 0 then
      @attr_hash[:email_address] = @rally_email_attr 
    else
      @attr_hash[:email_address] = @rally_login_name_attr
    end
    
    @attr_hash[:first_name] = @rally_first_name_attr if !@rally_first_name_attr.nil? && @rally_first_name_attr.length > 0
    @attr_hash[:last_name] = @rally_last_name_attr if !@rally_last_name_attr.nil? && @rally_last_name_attr.length > 0  
    @attr_hash[:display_name] = @rally_display_name_attr if !@rally_display_name_attr.nil? && @rally_display_name_attr.length > 0
    @attr_hash[:disabled] =  @ldap_inactive_attr if !@ldap_inactive_attr.nil? && @ldap_inactive_attr.length > 0
    @attrs = @attr_hash.values
  end
  
  def valid_entry?(entry)
    login_name = entry[@attr_hash[:login_name]][0]  
    
    if RALLY_LOGIN_REGEXP.match(login_name) 
      return true
    else
      return false
    end
  end
  
  def is_disabled?(entry)
    if @attr_hash.has_key?(:disabled) then
      if entry[@attr_hash[:disabled]][0] == @ldap_inactive_value
        return true
      else
        return false
      end  
    end
    return false
  end
  
  def get_fields(ldap_user)
    result = Hash.new
    result[:login_name] = ldap_user[@attr_hash[:login_name]][0]
    result[:first_name] = ldap_user[@attr_hash[:first_name]][0] if @attr_hash.has_key?(:first_name)
    result[:last_name]  = ldap_user[@attr_hash[:last_name]][0] if @attr_hash.has_key?(:last_name)
    result[:email_address] = ldap_user[@attr_hash[:email_address]][0] if @attr_hash.has_key?(:email_address)
    result[:display_name] = ldap_user[@attr_hash[:display_name]][0] if @attr_hash.has_key?(:display_name)
    result[:disabled] = 'false'
    result
  end  
  
  def set_user_permissions(user)
    @rally.user.subscription.workspaces.each { |workspace|
      if workspace.style == "UserStory" && workspace.state == 'Open'
        @user_helper.update_workspace_permissions(workspace, user, DEFAULT_PERMISSION, true)
      end
    }
  end    
end

def log_fatal_error(msg)
  @logger.error msg
  puts msg
end

class LogWrapper
  @logger = nil
  def initialize(log_file)
    @logger = Logger.new(log_file)
  end
  
  def info(msg)
    now = Time.now
    str = "#{now.strftime("%b %d %Y %H:%M:%S")}"
    @logger.info "#{str} #{msg}"
  end
  
  def error(msg)
    now = Time.now
    str = "#{now.strftime("%b %d %Y %H:%M:%S")}"    
    @logger.error "#{str} ERROR: #{msg}"

  end  
  
  def warn(msg)
    now = Time.now
    str = "#{now.strftime("%b %d %Y %H:%M:%S")}"    
    @logger.warn "#{str} WARN: #{msg}"

  end

  def level=(level)
    @logger.level = level
  end
end

class MissingTagError < StandardError
end