class Admin::GroupsController < Admin::ApplicationController
  before_filter :group, only: [:edit, :show, :update, :destroy, :project_update, :project_teams_update]

  def index
    @groups = Group.order('name ASC')
    @groups = @groups.search(params[:name]) if params[:name].present?
    @groups = @groups.page(params[:page]).per(20)
  end

  def show
  end

  def new
    @group = Group.new
  end

  def edit
  end

  def create
    group_path = params[:group][:name]
    params[:group][:name] = params[:group][:name].parameterize
    @group = Group.new(params[:group])
    @group.path = group_path if @group.name
    @group.owner = current_user

    if @group.save
      redirect_to [:admin, @group], notice: 'Group was successfully created.'
    else
      render action: "new"
    end
  end

  def update
    group_params = params[:group].dup
    owner_id =group_params.delete(:owner_id)

    if owner_id
      @group.owner = User.find(owner_id)
    end

    if @group.update_attributes(group_params)
      redirect_to [:admin, @group], notice: 'Group was successfully updated.'
    else
      render action: "edit"
    end
  end

  def project_update
    project_ids = params[:project_ids]

    Project.where(id: project_ids).each do |project|
      project.transfer(@group)
    end

    redirect_to :back, notice: 'Group was successfully updated.'
  end

  def remove_project
    @project = Project.find(params[:project_id])
    @project.transfer(nil)

    redirect_to :back, notice: 'Group was successfully updated.'
  end

  def project_teams_update
    @group.add_users_to_project_teams(params[:user_ids].split(','), params[:project_access])

    redirect_to [:admin, @group], notice: 'Users were successfully added.'
  end

  def destroy
    @group.truncate_teams

    @group.destroy

    redirect_to admin_groups_path, notice: 'Group was successfully deleted.'
  end

  private

  def group
    @group = Group.find_by_name(params[:id])
  end
end
