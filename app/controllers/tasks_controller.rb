class TasksController < AdminController
  load_and_authorize_resource

  def index
    @tasks = Task.incomplete.of_user(task_of_user)
    @users = find_users.order(:first_name, :last_name) unless current_user.case_worker?
  end

  # Calendar drag/drop + resize. load_and_authorize_resource satisfies the AC-3 guard, but
  # Task's CanCan grant is deliberately unscoped — re-find through of_user so a task outside
  # the caller's team 404s instead of being reschedulable by anyone.
  def reschedule
    @task = Task.of_user(current_user).find(params[:id])
    if @task.update(reschedule_params)
      head :ok
    else
      render json: @task.errors, status: :unprocessable_entity
    end
  end

  private

  def reschedule_params
    permitted = params.require(:task).permit(:completion_date, :start_time, :duration_minutes)
    # A drop into the all-day lane clears the time — and a timeless task can't keep a duration.
    permitted[:duration_minutes] = nil if permitted.key?(:start_time) && permitted[:start_time].blank?
    permitted
  end

  def find_users
    User.self_and_subordinates(current_user)
  end

  def task_of_user
    params[:user_id].present? ? User.find(params[:user_id]) : current_user
  end
end
