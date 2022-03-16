require 'rally_rest_api'

class ConnectionHelper
  
  def initialize(logger)
    @logger = logger
  end
  
  def connect_to_rally(default_connection)
    
    custom_headers = CustomHttpHeader.new
    custom_headers.name = 'LDAPConnector'
    custom_headers.version = '1.0.0-beta'
    custom_headers.vendor = 'RallySoftware'
    
    default_connection[:http_headers] = custom_headers
    
    begin
      @rally = RallyRestAPI.new(default_connection)
      @logger.info "Connecting to Rally: #{default_connection[:base_url]}"
      usecase_workspace_check?      
      @logger.info "Successfully connected to Rally"
      return @rally    
    rescue => ex      
      @logger.error "Could not connect to Rally"
      @logger.error "Error returned was: #{ex.message}"
      return nil  
    end
    
  end  
  
  def usecase_workspace_check? 
    usecase_found = false   
    @rally.user.subscription.workspaces.each { |workspace|  
      if workspace.style == "UseCase" && workspace.state == "Open"    
        @logger.info "Ignoring '#{workspace.name}' Use Case workspace"
        usecase_found = true
      end
    }  
    return usecase_found
  end
  
end
