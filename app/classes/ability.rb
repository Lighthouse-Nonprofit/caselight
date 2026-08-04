class Ability
  include CanCan::Ability

  # Phase 5.5 (AC-6): a single source of truth for the least-privilege flag. Read here ONLY.
  def self.least_privilege_enforced?
    # Phase 5 capstone: persisted per-tenant override if set, else the config.x boot default. Fails SAFE
    # to config.x (OFF) on any store error. `Ability#initialize` reads this once per build (current_ability
    # is per-request) -> a flip takes effect on the NEXT request's Ability. The force_least_privilege:
    # SHADOW seam is untouched (the shadow still builds a throwaway narrowed ability regardless).
    EnforcementSetting.enabled?(:enforce_least_privilege,
                                config_default: Rails.application.config.x.enforce_least_privilege == true)
  end

  # force_least_privilege is the SHADOW seam: LeastPrivilegeShadow builds a throwaway
  # Ability.new(user, force_least_privilege: true) to ask "what WOULD the narrowed rules
  # deny here" while the flag is OFF. Real (current_ability) builds pass nothing, so the
  # effective decision is the flag alone -> with the flag OFF @narrow is false everywhere
  # and the compiled CanCan rule set is identical to today.
  def initialize(user, force_least_privilege: false)
    @narrow = force_least_privilege || self.class.least_privilege_enforced?
    # Phase 5.3 — the gated assessment_domain attachment download is a custom member action; alias it
    # to :read so CanCan authorizes it via existing read rules. The field-level (domain sensitivity)
    # 403 is enforced inside AssessmentsController#download_attachment, not by CanCan.
    alias_action :download_attachment, to: :read
    # S5 — the school hub's READ-ONLY tabs are custom Agency actions; without an
    # alias, roles that hold :read but not :manage on Agency (strategic
    # overviewer) get the tab links rendered and then denied. Write surfaces
    # (report cards, roll call) stay gated on :create ClientEnrollmentTracking.
    alias_action :roster, :cohorts, :cohort, to: :read
    can :manage, Agency
    can :manage, ReferralSource
    can :manage, QuarterlyReport
    can :read, ProgramStream
    can :preview, ProgramStream
    # Phase 5.4 — break-glass: any signed-in user may ATTEMPT a self-elevation. The controller
    # still gates it on already being able to :read the target record (accessible_by), so this
    # `can` only authorizes REACHING the endpoint, not the access itself (bypass E — keeps
    # load_and_authorize_resource from blocking the cross-caseload load). admin already has
    # `can :manage, :all`. strategic_overviewer reaching it is harmless: SensitivityPolicy keeps
    # them standard-only even WITH a self-created grant.
    # NB the SYMBOL :break_glass_grant (not the class): the controller uses
    # `load_and_authorize_resource class: false`, which authorizes the action against the symbolized
    # controller name, so a `can :create, BreakGlassGrant` (class) rule would NOT match.
    can :create, :break_glass_grant

    # Phase 5.6 follow-up fix: the notifications page authorizes the SYMBOL :notification (there is
    # no Notification model — the data is UserNotification, a current_user-scoped PORO). The original
    # 5.6 edit authorized the bare constant, so /notifications raised NameError (500) for every role;
    # the grant its comment described was also never added. Same class-less pattern as above.
    can :read, :notification

    if user.admin?
      can :manage, :all
    elsif user.strategic_overviewer?
      cannot :manage, AbleScreeningQuestion
      cannot :manage, Agency
      cannot :manage, ReferralSource
      cannot :manage, QuarterlyReport
      cannot :manage, CustomFieldProperty

      can :read, :all
      # Phase 5.5: strategic_overviewer => NO paper_trail history when enforced (locked decision).
      # Version history (paper_trail object/object_changes) can carry pre-encryption plaintext that
      # 5.3 masks on the live record (POAM-SC28-HIST), so it is a masking-bypass channel for an
      # oversight role that should see standard live fields only. read:all / report:all stay BROAD
      # (org-wide oversight read is plausibly its need-to-know; 5.3 already masks sensitive fields).
      can :version, :all unless @narrow
      # Phase 5.5: the per-record :version removal above does NOT close the ORG-WIDE paper_trail
      # browse at /data_trackers#index (it is authorized via :read against the empty DataTracker hook
      # model, NOT :version). Per DP-2 (recommended Option A), close the dashboard too when enforcing.
      # If the org ratifies the change-audit dashboard as oversight need-to-know, drop this one line.
      cannot :read, DataTracker if @narrow
      can :report, :all
      # Reports batch: leadership tier (read-only; sensitivity masking keeps the
      # overviewer standard-only inside every report).
      can %i[report_worker report_manager report_leadership], :report

      cannot :manage, CaseNote
      # UX round 3 (B2/B3): household notes + alerts mirror the CaseNote treatment — narrative
      # PII is outside the oversight role's need-to-know entirely (cannot :manage revokes
      # :read too; the alert banner/chip are likewise hidden from this role).
      cannot :manage, FamilyNote
      cannot :manage, FamilyAlert
    elsif user.case_worker?
      # Reports batch: worker tier — the reports library scoped to THEIR caseload
      # (every report queries through Client.accessible_by, so the rules below
      # bound the data; the tier symbol bounds which report definitions run).
      can %i[index show], :report
      can :report_worker, :report
      can :manage, AbleScreeningQuestion
      can :manage, Assessment
      can :manage, Attachment
      can :manage, Case, exited: false
      can :manage, CaseNote
      can :create, Client
      can :manage, Client, case_worker_clients: { user_id: user.id }
      # UX round 3 (B4/R10): household-level context is case-relevant — case workers read the
      # HOUSEHOLDS of their own caseload (never the org-wide list), plus caseload-scoped
      # household notes (read/write) and alerts (read-only; raising stays with managers).
      caseload_family = { cases: { client: { case_worker_clients: { user_id: user.id } } } }
      can :read, Family, caseload_family
      can :read,   FamilyNote,  family: caseload_family
      can :create, FamilyNote,  family: caseload_family
      can :read,   FamilyAlert, family: caseload_family
      can :manage, ProgressNote
      can :manage, Task
      can :manage, CustomFieldProperty, custom_formable_type: 'Client'
      can :manage, ClientEnrollment
      can :manage, ClientEnrollmentTracking
      can :manage, LeaveProgram
      can :update, Assessment do |assessment|
        assessment.client.user_id == user.id
      end
      cannot :update, Assessment do |assessment|
        Date.current > assessment.created_at + 2.weeks
      end
    elsif user.able_manager?
      can %i[index show], :report
      can :report_worker, :report
      can :manage, AbleScreeningQuestion
      can :manage, Assessment
      can :manage, Attachment
      can :manage, CaseNote
      can :create, Client
      can :manage, Client, able_state: Client::ABLE_STATES
      can :manage, Client, case_worker_clients: { user_id: user.id }
      # UX round 3 (B4/R10): mirror the role's Client union (able_state OR own caseload) with
      # two ORed rules per resource — the same pattern as the Phase-5.5 ProgressNote scoping.
      can :read, Family, cases: { client: { able_state: Client::ABLE_STATES } }
      can :read, Family, cases: { client: { case_worker_clients: { user_id: user.id } } }
      can :read, FamilyNote,  family: { cases: { client: { able_state: Client::ABLE_STATES } } }
      can :read, FamilyNote,  family: { cases: { client: { case_worker_clients: { user_id: user.id } } } }
      can :create, FamilyNote, family: { cases: { client: { case_worker_clients: { user_id: user.id } } } }
      can :read, FamilyAlert, family: { cases: { client: { able_state: Client::ABLE_STATES } } }
      can :read, FamilyAlert, family: { cases: { client: { case_worker_clients: { user_id: user.id } } } }
      can :manage, ProgressNote
      can :manage, Task
      can :manage, CustomFieldProperty, custom_formable_type: "Client"
      can :manage, CustomField
      can :manage, ClientEnrollment
      can :manage, ClientEnrollmentTracking
      can :manage, LeaveProgram
      can :update, Assessment do |assessment|
        assessment.client.able?
      end
      cannot :update, Assessment do |assessment|
        Date.current > assessment.created_at + 2.weeks
      end
    elsif user.ec_manager?
      can %i[index show], :report
      can :report_worker, :report
      can :create, Client
      can :manage, Client, status: 'Active EC'
      can :manage, Client, case_worker_clients: { user_id: user.id }
      can :manage, CaseNote
      # Phase 5.5: scope ProgressNote read to the role's need-to-know. The role's Client access is a
      # STATUS-OR-CASELOAD union (status 'Active EC' OR own caseload), so mirror BOTH with two ORed
      # rules -- caseload-only would deny notes for Active-EC clients the role reaches by program
      # status (and is already admitted onto the page by find_client's union accessible_by).
      # ProgressNote belongs_to :client; Client has_many :case_worker_clients.
      if @narrow
        can :read, ProgressNote, client: { status: 'Active EC' }
        can :read, ProgressNote, client: { case_worker_clients: { user_id: user.id } }
      else
        can :read, ProgressNote
      end
      can :manage, Family
      can :manage, FamilyNote
      can :manage, FamilyAlert
      can :manage, Partner
      can :manage, Case, { case_type: 'EC', exited: false }
      can :manage, Assessment
      can :manage, Task
      can :manage, CustomFieldProperty, custom_formable_type: 'Client'
      can :manage, CustomFieldProperty, custom_formable_type: 'Family'
      can :manage, CustomFieldProperty, custom_formable_type: 'Partner'
      can :manage, CustomField
      can :manage, ClientEnrollment
      can :manage, ClientEnrollmentTracking
      can :manage, LeaveProgram
      can :update, Assessment do |assessment|
        assessment.client.active_ec?
      end
      cannot :update, Assessment do |assessment|
        Date.current > assessment.created_at + 2.weeks
      end
    elsif user.fc_manager?
      can %i[index show], :report
      can :report_worker, :report
      can :create, Client
      can :manage, Client, status: 'Active FC'
      can :manage, Client, case_worker_clients: { user_id: user.id }
      can :manage, CaseNote
      # Phase 5.5: scope ProgressNote read to status 'Active FC' OR own caseload (mirrors the role's
      # two Client rules -- see ec_manager note above for the union rationale).
      if @narrow
        can :read, ProgressNote, client: { status: 'Active FC' }
        can :read, ProgressNote, client: { case_worker_clients: { user_id: user.id } }
      else
        can :read, ProgressNote
      end
      can :manage, Family
      can :manage, FamilyNote
      can :manage, FamilyAlert
      can :manage, Partner
      can :manage, Case, { case_type: 'FC', exited: false }
      can :manage, Assessment
      can :manage, Task
      can :manage, CustomFieldProperty, custom_formable_type: 'Client'
      can :manage, CustomFieldProperty, custom_formable_type: 'Family'
      can :manage, CustomFieldProperty, custom_formable_type: 'Partner'
      can :manage, CustomField
      can :manage, ClientEnrollment
      can :manage, ClientEnrollmentTracking
      can :manage, LeaveProgram
      can :update, Assessment do |assessment|
        assessment.client.active_fc?
      end
      can :read, Attachment
      cannot :update, Assessment do |assessment|
        Date.current > assessment.created_at + 2.weeks
      end
    elsif user.kc_manager?
      can %i[index show], :report
      can :report_worker, :report
      can :create, Client
      can :manage, Client, status: 'Active KC'
      can :manage, Client, case_worker_clients: { user_id: user.id }
      can :manage, CaseNote
      # Phase 5.5: scope ProgressNote read to status 'Active KC' OR own caseload (mirrors the role's
      # two Client rules -- see ec_manager note above for the union rationale).
      if @narrow
        can :read, ProgressNote, client: { status: 'Active KC' }
        can :read, ProgressNote, client: { case_worker_clients: { user_id: user.id } }
      else
        can :read, ProgressNote
      end
      can :manage, Family
      can :manage, FamilyNote
      can :manage, FamilyAlert
      can :manage, Partner
      can :manage, Case, { case_type: 'KC', exited: false }
      can :manage, Assessment
      can :manage, Task
      can :manage, CustomFieldProperty, custom_formable_type: 'Client'
      can :manage, CustomFieldProperty, custom_formable_type: 'Family'
      can :manage, CustomFieldProperty, custom_formable_type: 'Partner'
      can :manage, CustomField
      can :manage, ClientEnrollment
      can :manage, ClientEnrollmentTracking
      can :manage, LeaveProgram
      can :update, Assessment do |assessment|
        assessment.client.active_kc?
      end
      cannot :update, Assessment do |assessment|
        Date.current > assessment.created_at + 2.weeks
      end
      can :read, Attachment
    elsif user.manager?
      # Reports batch: worker + manager tiers (team-scoped via the Client rules below).
      can %i[index show], :report
      can %i[report_worker report_manager], :report
      can :manage, AbleScreeningQuestion
      can :create, Client
      # Phase 5.5: compute the manager's team-user-id set ONCE and reuse it for BOTH the Client rule
      # and the new (narrowed) ProgressNote rule, so the two rules cannot drift. Character-identical
      # to the expression that previously lived inline on the Client rule (pure refactor when OFF).
      team_ids = User.where('manager_ids && ARRAY[:user_id]::integer[] OR id = :user_id', { user_id: user.id }).map(&:id)
      can :manage, Client, case_worker_clients: { user_id: team_ids }
      can :manage, User, id: User.where('manager_ids && ARRAY[?]::integer[]', user.id).map(&:id)
      can :manage, User, id: user.id
      can :manage, Case
      can :manage, Task
      can :manage, Assessment
      can :manage, CaseNote
      can :manage, Family
      can :manage, FamilyNote
      can :manage, FamilyAlert
      can :manage, Partner
      can :manage, CustomFieldProperty, custom_formable_type: 'Client'
      can :manage, CustomFieldProperty, custom_formable_type: 'Family'
      can :manage, CustomFieldProperty, custom_formable_type: 'Partner'
      can :manage, CustomField
      can :manage, ClientEnrollment
      can :manage, ClientEnrollmentTracking
      can :manage, LeaveProgram
      # Phase 5.5: scope ProgressNote read to the manager's TEAM caseload (reuse team_ids above),
      # not org-wide. Manager Client access is team-caseload only (no status branch), so a single
      # narrowed rule matches the Client population exactly.
      if @narrow
        can :read, ProgressNote, client: { case_worker_clients: { user_id: team_ids } }
      else
        can :read, ProgressNote
      end
    end

    # Phase 6 (deletion lifecycle, AC-6): under least-privilege narrowing, destroying an individual
    # becomes ADMIN-ONLY. Placed after the role branches so CanCan's later-rule-wins strips :destroy
    # from every non-admin role's `can :manage, Client` in one place. Shadow-first like the other
    # @narrow rules: with the flag OFF this is inert; would-be denials surface in the AccessReview
    # least-privilege shadow table before any flip. The unconditional associated-records guard in
    # ClientsController#destroy protects the dangerous cascade regardless of this flag.
    cannot :destroy, Client if @narrow && !user.admin?
  end
end
