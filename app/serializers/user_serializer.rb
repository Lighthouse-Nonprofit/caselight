class UserSerializer < ActiveModel::Serializer
  # POAM-016: pin_number is a staff credential-adjacent secret and must not be emitted on the API
  # surface (no consumer reads it here — verified). Dropped from the attribute list.
  attributes :id, :first_name, :last_name, :email, :roles, :mobile, :date_of_birth, :archived, :admin, :manager_id, :clients

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
