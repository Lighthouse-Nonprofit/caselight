class TaskHistory
  include Mongoid::Document
  include Mongoid::Timestamps

  default_scope { where(tenant: Organization.current.try(:short_name)) }

  field :object, type: Hash
  field :tenant, type: String, default: ->{ Organization.current.short_name }

  embeds_many :case_worker_task_histories

  after_save :create_case_worker_task_history, if: -> { object.key?("user_ids") }

  def self.initial(task)
    # Phase 6 (SC-28 / POAM-SC28-HIST): scrub encrypted attributes from the snapshot (a no-op for
    # Task today; future-proof). StaffMonthlyReport reads object.completion_date / completed /
    # user_ids — all non-PII, all preserved.
    attributes = HistoryPiiFilter.scrub(Task, task.attributes)
    attributes = attributes.merge('user_ids' => task.user_ids) if task.user_ids.any?
    create(object: attributes)
  end

  private

  def create_case_worker_task_history
    # Phase 6: staff snapshot scrubbed (email/names/mobile/credentials/sign-in IPs removed); the old
    # IP-stringify lines would re-add the keys as "" post-scrub, so they are gone.
    object['user_ids'].each do |user_id|
      case_worker = HistoryPiiFilter.scrub(User, User.find_by(id: user_id).try(:attributes))
      case_worker_task_histories.create(object: case_worker)
    end
  end
end
