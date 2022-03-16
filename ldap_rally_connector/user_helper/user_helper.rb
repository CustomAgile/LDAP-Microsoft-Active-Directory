require 'rally_rest_api'

class UserHelper
  
  #Setup constants
  ADMIN = 'Admin'
  USER = 'User'
  EDITOR = 'Editor'
  VIEWER = 'Viewer'
  NOACCESS = 'No Access'
  
  def initialize(rally, logger, create_flag = true)
    @rally = rally
    @logger = logger 
    @create_flag = create_flag
  end
  
  # Helper methods
  # Does the user exist? If so, return the user, if not return nil
  # Need to downcase the name since user names are downcased when created. Without downcase, we would not be
  #  able to find 'Mark@acme.com'
  def find_user(name)  
    
    if ( name.downcase != name )
      @logger.info "Looking for #{name.downcase} instead of #{name}"
    end
    query_result = @rally.find(:user, :fetch => true, :pagesize => 100) { equal :login_name, name.downcase }
    
    if query_result.total_result_count == 0
      return nil
    else
      return query_result.results.first
    end
  end
  
  def find_workspace(name)
    workspace = @rally.user.subscription.workspaces.find { |w| w.name == name }
    if workspace == nil
      @logger.error "Rally Workspace #{name} not found"
    end
    workspace
  end
  
  def update_workspace_permissions(workspace, user, permission, new_user)
    if new_user or permissions_updated?(workspace, user, permission)
      update_permissions(workspace, user, permission)
    else
      @logger.info "  #{user.login_name} #{workspace.name} - No permission changes"
    end
  end
  
  def create_user(login_name, display_name, first_name, last_name)
    fields = {
      :login_name => login_name.downcase,
      :email_address => login_name.downcase
    }
    fields.merge!(gather_user_fields(display_name, first_name, last_name))
    
    user = create_user_with_hash(fields)
  end
  
  def create_user_with_hash(fields)
    user = nil
    begin
      if @create_flag
        user = @rally.create(:user, fields) 
      end

      @logger.info "Created Rally user #{fields[:login_name]}"
    rescue         
      @logger.error "Error creating user: #{$!}"
      raise $!
      return nil
    end
    return user
  end
  
  def disable_user(user)
    if user.disabled == 'false'
      if @create_flag 
        @rally.update(user, :disabled => true)
      end
      
      @logger.info "#{user.login_name} disabled in Rally"   
    else
      @logger.info "#{user.login_name} already disabled from Rally" 
      return false
    end   
    return true
  end
  
  def enable_user(user)
    if user.disabled == 'true'
      @rally.update(user, :disabled => 'false') if @create_flag
      @logger.info "#{user.login_name} enabled in Rally"
      return true
    else
      @logger.info "#{user.login_name} already enabled in Rally"
      return false
    end
  end
  
  # Create Admin, User, or Viewer permissions for a Workspace
  def create_workspace_permission(user, workspace, permission)
    # Keep backward compatibility of our old permission names
    # TODO is this in the right place or should we remove from this helper?
    if permission == VIEWER || permission == EDITOR
      permission = USER
    end
    
    fields = {
      :workspace => workspace,
      :user => user,
      :role => permission
    }
    @rally.create(:workspace_permission, fields) if @create_flag
  end

  def gather_user_fields(display_name, first_name, last_name)
    fields = {
      :display_name => display_name,
      :first_name => first_name,
      :last_name => last_name
    }
  end
  
  #--------- Private methods --------------
  private
  
  # Takes the name of the permission and returns the last token which is the permission
  def parse_permission(name)
    if name.reverse.index(VIEWER.reverse)
      return VIEWER
    elsif name.reverse.index(EDITOR.reverse)
      return EDITOR
    elsif name.reverse.index(USER.reverse)
      return USER
    elsif name.reverse.index(ADMIN.reverse)
      return ADMIN
    else
      @logger.info "Error in parsing permission"
    end
    nil
  end
  
  # Return only the project permissions from one workspace
  # We do this since queries on permissions are a bit limited - to only one filter parameter
  def findProjectPermissions(workspace, user)
    query_result = @rally.find(:project_permission, :fetch => true, :pagesize => 100) {
      equal :"user.login_name", user.login_name
    }
    
    projectPermissions = []
    query_result.each { |pp|
      if ( pp.project.workspace == workspace)
        projectPermissions.push(pp)
      end
    }
    projectPermissions
  end
  
  # check if the new permissions are different than what the user currently has
  # if we don't do this, we will delete and recreate permissions each time and that
  # will make the revision history on user really, really, really, really ugly
  # TODO - this is slow because we re-query the permissions for each workspace
  def permissions_updated?(workspace, user, new_permission)
    projectPermissions = findProjectPermissions(workspace, user)
    
    changed = false
    
    # If a project has been added, update all permissions
    if (projectPermissions.length != workspace.projects.length )
      changed = true
    else # Look though each project permission to see if they are different than the new_permission
      projectPermissions.each { |pp|
          if parse_permission(pp.role) != new_permission
            changed = true
          end
      }
    end
    
    changed
  end
  
  # Create User or Viewer permissions for a Project
  def create_project_permission(user, project, permission)
  # Keep backward compatibility of our old permission names
  # TODO is this in the right place or should we remove from this helper?
    if permission == USER
      permission = EDITOR
    end

    fields = {
      :project => project,
      :user => user,
      :role => permission
    }
    @rally.create(:project_permission, fields) if @create_flag
  end
  
  # Project permissions are automatically deleted in this case
  # TODO: I think there is a bug in removing permissions once you have them, not sure though
  def delete_workspace_permission(user, workspace)
    # queries on permissions are a bit limited - to only one filter parameter
    query_result = @rally.find(:workspace_permission, :fetch => true, :pagesize => 100) {
      equal :"user.login_name", user.login_name
    }
    
    # So now we need to find the exact workspace for all the users workspace_permissions
    workspace_permission = nil
    workspace_permission = query_result.find { |wp| wp.workspace == workspace }
    # delete it if it exists
    if workspace_permission != nil
      workspace_permission.delete
    end
  end
  
  def update_permissions(workspace, user, permission)
    @logger.info "  #{user.login_name} #{workspace.name} - Permission changed to #{permission}"
    if permission == ADMIN
      create_workspace_permission(user, workspace, permission)
    elsif permission == NOACCESS
      delete_workspace_permission(user, workspace)
    elsif permission == USER || permission == VIEWER || permission == EDITOR
      create_workspace_permission(user, workspace, permission) 
      workspace.projects.each { |project|
        create_project_permission(user, project, permission)
      }
    else
      @logger.error "Invalid Permission - #{permission}"
    end
  end

end
