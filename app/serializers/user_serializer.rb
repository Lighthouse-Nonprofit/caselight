class UserSerializer < ActiveModel::Serializer
  attributes :id, :first_name, :last_name, :email, :roles, :mobile, :date_of_birth, :archived, :admin, :manager_id, :pin_number, :clients

  def clients
    object.clients.map do |client|
      incompleted_tasks = client.tasks.incomplete
      formatted_client  = client.as_json(only: [:id, :given_name, :family_name, :local_given_name, :local_family_name])
      overdue_tasks     = ActiveModelSerializers::SerializableResource.new(incompleted_tasks.overdue, each_serializer: TaskSerializer, adapter: :attributes).as_json
      today_tasks       = ActiveModelSerializers::SerializableResource.new(incompleted_tasks.today, each_serializer: TaskSerializer, adapter: :attributes).as_json
      upcoming_tasks    = ActiveModelSerializers::SerializableResource.new(incompleted_tasks.upcoming, each_serializer: TaskSerializer, adapter: :attributes).as_json

      formatted_client.merge(overdue: overdue_tasks, today: today_tasks, upcoming: upcoming_tasks)
    end.compact
  end
end
