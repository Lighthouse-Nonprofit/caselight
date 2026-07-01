class User < ActiveRecord::Base
  include EntityTypeCustomField
  include EntityTypeCustomFieldNotification
  include NextClientEnrollmentTracking
  include ClientEnrollmentTrackingNotification

  ROLES = ['admin', 'case worker', 'able manager', 'ec manager', 'fc manager', 'kc manager', 'manager', 'strategic overviewer'].freeze
  MANAGERS = ROLES.select { |role| role if role.include?('manager') }

  # Authentication modules:
  #  - :two_factor_authenticatable REPLACES :database_authenticatable (it `include`s it) and adds the
  #    TOTP login strategy + `encrypts :otp_secret`. It is the ONLY password strategy, so MFA cannot be
  #    bypassed by a password-only strategy. MFA is OPT-IN: otp_required_for_login defaults false, so
  #    users without MFA log in with email+password as before (see TwoFactorSettingsController).
  #  - :two_factor_backupable adds one-time recovery codes (otp_backup_codes).
  #  - :secure_validatable = password complexity, :password_archivable = no-reuse (IA-5),
  #    :lockable = AC-7, :timeoutable = AC-12.
  # FedRAMP IA-2(1) / IA-5 / AC-7 / AC-12, SC-28.
  devise :two_factor_authenticatable, :two_factor_backupable, :registerable,
         :recoverable, :rememberable, :trackable, :secure_validatable,
         :lockable, :timeoutable, :password_archivable, :password_expirable

  # --- MFA helpers ---
  # Whether this account has TOTP two-factor enabled (i.e. completed enrollment).
  def two_factor_enabled?
    otp_required_for_login?
  end

  # Privileged accounts (admin + any manager role) — the set FedRAMP IA-2(1) ultimately requires MFA
  # for. The enforcement check (ApplicationController#require_mfa_for_privileged) is gated behind a
  # config flag that defaults OFF, so this is informational until the org switches enforcement on.
  def mfa_privileged?
    roles == 'admin' || roles.to_s.include?('manager')
  end

  # === Runtime-enforcing security toggles (per-tenant, fail-safe to Devise config) ===================
  # Each reads the CURRENT Apartment tenant's EnforcementSetting via the tenant-keyed request memo and
  # falls back to the Devise config default when unset/blank/error. With no row/blank column every one of
  # these is byte-identical to today.

  # Toggle 2 (AC-12 idle-session timeout). Devise Timeoutable calls this INSTANCE method per user
  # (Devise::Models::Timeoutable#timeout_in). Blank/error => super => self.class.timeout_in => 30 min.
  # Range 1..1440 is enforced at write, so a bad value can never be stored.
  def timeout_in
    mins = EnforcementSetting.effective_value(:idle_timeout_minutes, config_default: nil)
    mins.present? ? mins.to_i.minutes : super
  end

  # Toggle 3 (AC-7 lockout). Devise Lockable reads these at the CLASS level
  # (Devise::Models::Lockable::ClassMethods). super reaches the Devise config reader (10 / 1.hour).
  # ADMIN-BRICK FLOOR: maximum_attempts clamps to >= LOCKOUT_ATTEMPTS_FLOOR (3) even if a bad value
  # reached the DB (the model also validates >= 3, so it can't be persisted through the panel).
  def self.maximum_attempts
    v = EnforcementSetting.effective_value(:lockout_max_attempts, config_default: nil)
    v.present? ? [v.to_i, EnforcementSetting::LOCKOUT_ATTEMPTS_FLOOR].max : super
  end

  def self.unlock_in
    mins = EnforcementSetting.effective_value(:lockout_unlock_in_minutes, config_default: nil)
    mins.present? ? mins.to_i.minutes : super
  end

  # Toggle 4 (IA-5 password max age). devise-security :password_expirable provides the whole feature —
  # before_save stamping of password_changed_at on encrypted_password change, need_change_password? /
  # password_expired?, the auto-included handle_password_change before_action (already on every controller
  # today, inert), and Devise::PasswordExpiredController + view + route. We ONLY override the config reader.
  #
  # SHIP-BLOCKER NEUTRALIZER: the gem's GLOBAL default is Devise.expire_password_after == 3.months
  # (verified in the container). Returning FALSE when unset makes password_expiration_enabled? false =>
  # need_change_password? false => zero redirects (feature OFF); WITHOUT this, enabling the module would
  # force-expire EVERY user on their next login.
  #
  # FOOTGUN NOTE: the gem's `with_expired_password` / `without_expired_password` class scopes call
  # `expire_password_after.seconds` and will raise NoMethodError (false.seconds) while expiry is OFF. They
  # are never called by the app or by devise-security internals today; guard any future caller with a
  # positive day count or password_expiration_enabled? before invoking them.
  def self.expire_password_after
    days = EnforcementSetting.effective_value(:password_max_age_days, config_default: nil)
    days.present? ? days.to_i.days : false
  end

  has_paper_trail


  belongs_to :province,   counter_cache: true
  belongs_to :department, counter_cache: true
  belongs_to :manager, class_name: 'User', foreign_key: :manager_id, required: false

  has_many :changelogs, dependent: :restrict_with_error
  has_many :progress_notes, dependent: :restrict_with_error
  has_many :case_worker_clients, dependent: :restrict_with_error
  has_many :clients, through: :case_worker_clients
  has_many :case_worker_tasks, dependent: :destroy
  has_many :tasks, through: :case_worker_tasks
  has_many :visits,  dependent: :destroy
  has_many :visit_clients,  dependent: :destroy
  has_many :calendars, dependent: :destroy
  has_many :custom_field_properties, as: :custom_formable, dependent: :destroy
  has_many :custom_fields, through: :custom_field_properties, as: :custom_formable
  # WebAuthn passkeys (FedRAMP IA-2). ADDITIVE login factor; see WebauthnCredential + SessionsController.
  has_many :webauthn_credentials, dependent: :destroy

  validates :roles, presence: true, inclusion: { in: ROLES }
  # Tier 3 encrypts :email deterministically + downcase, so the ciphertext is case-folded + stable.
  # uniqueness MUST be case_sensitive: true — case_sensitive:false builds LOWER(<ciphertext>), which never
  # matches; downcase:true already makes 'A@x.org'/'a@x.org' collide on the same ciphertext.
  validates :email, presence: true, uniqueness: { case_sensitive: true }

  # Phase 4 Tier 3 — DETERMINISTIC field encryption of staff-account PII (FedRAMP SC-28, SOC 2 C1.1).
  # Same plaintext => same ciphertext, so equality lookups + the users.email UNIQUE index still work;
  # iLIKE/range/ORDER BY do NOT (the *_like scopes below are now exact where()s; name sorts moved
  # in-memory at the call sites). :email is the Devise login identifier — downcase:true makes the
  # deterministic ciphertext case-fold on BOTH the write and the find_for_database_authentication equality
  # query (Devise already strips whitespace via strip_whitespace_keys), so a mixed-case login still
  # matches. :uid is the vestigial devise_token_auth column the 2016 migration set = email — encrypted
  # with the SAME scheme so it stops leaking a plaintext email copy. CRITICAL DEPLOY ORDERING: the email
  # backfill MUST run in the SAME step as this declaration, BEFORE login — a not-yet-backfilled plaintext
  # email won't match the deterministic equality query (support_unencrypted_data tolerates the READ, but
  # the WHERE compares ciphertext) => that user can't log in. Run: db:migrate + apartment:migrate ->
  # rake encryption:backfill TIER=3 CONFIRM=1 -> rake encryption:verify TIER=3 -> then login is safe.
  encrypts :email, deterministic: true, downcase: true
  encrypts :uid,   deterministic: true, downcase: true
  encrypts :first_name, deterministic: true
  encrypts :last_name,  deterministic: true
  encrypts :mobile,     deterministic: true

  # Tier 3: these 4 columns are DETERMINISTICALLY encrypted — iLIKE substring matching over ciphertext is
  # impossible; exact equality still works. Rewritten to exact where(col: value) (names kept so UserGrid
  # filters + the existing user_spec scope tests need no rename). :email matches case-insensitively via
  # downcase:true; first_name/last_name/mobile are exact (case/whitespace sensitive). Substring search is gone.
  scope :first_name_like, ->(value) { where(first_name: value) }
  scope :last_name_like,  ->(value) { where(last_name: value) }
  scope :mobile_like,     ->(value) { where(mobile: value) }
  scope :email_like,      ->(value) { where(email: value) }
  scope :in_department,   ->(value) { where('department_id = ?', value) }
  scope :job_title_are,   ->        { where.not(job_title: '').pluck(:job_title).uniq }
  scope :department_are,  ->        { joins(:department).pluck('departments.name', 'departments.id').uniq }
  scope :case_workers,    ->        { where(roles: 'case worker') }
  scope :admins,          ->        { where(roles: 'admin') }
  scope :province_are,    ->        { joins(:province).pluck('provinces.name', 'provinces.id').uniq }
  scope :has_clients,     ->        { joins(:clients).without_json_fields.distinct }
  scope :managers,        ->        { where(roles: MANAGERS) }
  scope :able_managers,   ->        { where(roles: 'able manager') }
  scope :ec_managers,     ->        { where(roles: 'ec manager') }
  scope :fc_managers,     ->        { where(roles: 'fc manager') }
  scope :kc_managers,     ->        { where(roles: 'kc manager') }
  scope :non_strategic_overviewers, -> { where.not(roles: 'strategic overviewer') }
  scope :staff_performances,         -> { where(staff_performance_notification: true) }

  before_save :assign_as_admin
  before_save :set_manager_ids, if: :manager_id_changed?
  after_save :reset_manager, if: :saved_change_to_roles?

  ROLES.each do |role|
    define_method("#{role.parameterize.underscore}?") do
      roles == role
    end
  end

  def active_for_authentication?
    super && !disable?
  end

  def name
    full_name = "#{first_name} #{last_name}"
    full_name.present? ? full_name : 'Unknown'
  end

  def assign_as_admin
    self.admin = true if admin?
  end

  def self.without_json_fields
    select(column_names - ['tokens'])
  end

  def any_case_manager?
    ec_manager? || fc_manager? || kc_manager?
  end

  def any_manager?
    any_case_manager? || able_manager? || manager?
  end

  def no_any_associated_objects?
    clients_count.zero? && tasks_count.zero? && changelogs_count.zero? && progress_notes.count.zero?
  end

  def client_status
    case roles
    when 'ec manager'
      'Active EC'
    when 'fc manager'
      'Active FC'
    when 'kc manager'
      'Active KC'
    end
  end

  def assessment_either_overdue_or_due_today
    overdue   = []
    due_today = []
    clients.all_active_types.each do |client|
      client_next_asseement_date = client.next_assessment_date.to_date
      if client_next_asseement_date < Date.today
        overdue << client
      elsif client_next_asseement_date == Date.today
        due_today << client
      end
    end
    { overdue_count: overdue.count, due_today_count: due_today.count }
  end

  def assessments_overdue
    clients.all_active_types
  end

  def client_custom_field_frequency_overdue_or_due_today
    entity_type_custom_field_notification(clients)
  end

  def user_custom_field_frequency_overdue_or_due_today
    if self.manager?
      entity_type_custom_field_notification(User.where('manager_ids && ARRAY[?]::integer[]', self.id))
    elsif self.admin?
      entity_type_custom_field_notification(User.all)
    end
  end

  def partner_custom_field_frequency_overdue_or_due_today
    if self.admin? || self.any_case_manager? || self.manager?
      entity_type_custom_field_notification(Partner.all)
    end
  end

  def family_custom_field_frequency_overdue_or_due_today
    if self.admin? || self.any_case_manager? || self.manager?
      entity_type_custom_field_notification(Family.all)
    end

  end

  def client_enrollment_tracking_overdue_or_due_today
    client_enrollment_tracking_notification(clients)
  end

  def self.self_and_subordinates(user)
    if user.admin? || user.strategic_overviewer?
      User.all
    elsif user.manager?
      User.where('id = :user_id OR manager_ids && ARRAY[:user_id]::integer[]', { user_id: user.id })
    elsif user.able_manager?
      user_ids = Client.able.map(&:user_ids).flatten << user.id
      User.where(id: user_ids.uniq)
    elsif user.any_case_manager?
      user_ids = [user.id]
      if user.ec_manager?
        user_ids << Client.active_ec.map(&:user_ids).flatten
      elsif user.fc_manager?
        user_ids << Client.active_fc.map(&:user_ids).flatten
      elsif user.kc_manager?
        user_ids << Client.active_kc.map(&:user_ids).flatten
      end
      User.where(id: user_ids.flatten.uniq)
    end
  end

  def reset_manager
    # In an after_save, Rails 5.2 deprecated the pre-save dirty API (roles_change) in favor of the
    # post-save API; saved_change_to_roles returns [old, new] for the just-completed save (or nil).
    new_role = saved_change_to_roles&.last
    if new_role == 'case worker' || new_role == 'strategic overviewer'
      User.where(manager_id: self).map{|u| u.update(manager_id: nil)}
    end
  end

  def set_manager_ids
    if manager_id.nil?
      self.manager_ids = []
      return if manager_id_was == self.id
      update_manager_ids(self)
    else
      manager_ids = User.find(self.manager_id).manager_ids
      update_manager_ids(self, manager_ids.unshift(self.manager_id))
    end
  end

  def update_manager_ids(user, manager_ids = [])
    user.manager_ids = manager_ids
    user.save unless user.id == id
    return if user.case_worker?
    case_workers = User.where(manager_id: user.id)
    if case_workers.present?
      case_workers.each do |case_worker|
        update_manager_ids(case_worker, manager_ids.unshift(user.id))
      end
    end
  end
end
