# frozen_string_literal: true
require 'rails_helper'

# Phase 5.6 (AC-3) HARD-CI GUARD -- the durable mandatory-authorization invariant. FAILS if ANY routed +
# IMPLEMENTED controller action is NEITHER authorizing NOR allowlisted, so a future controller cannot
# silently reintroduce default-open. Pure static introspection (no DB / no sign-in).
#
# Reconstructs the EXACT decision check_authorization makes, via CanCanCan's own before_action Procs
# (verified by source_location):
#   AUTHORIZES  = a :before callback Proc from cancancan controller_resource.rb (load_and_authorize_resource
#                 / authorize_resource), whose only:/except: applies to this action.
#   ALLOWLISTED = a :before callback Proc from cancancan controller_additions.rb (skip_authorization_check),
#                 scoped to this action.
# In-BODY authorize! (e.g. access_reviews#index, break_glass_grants#create, the 5.6 hole fixes, the two
# resolved shells) is invisible to the scan, so those live in a small REVIEWED allowmap. Routes come from
# the real route table INTERSECTED with klass.action_methods (drops phantom RESTful routes from dead
# `resources :calendars/:clients/:custom_fields`).
RSpec.describe 'Phase 5.6 authorization coverage guard', type: :request do
  IN_BODY_AUTHORIZE = {
    'access_reviews'               => %w[index],         # authorize! :read, :access_review
    'break_glass_grants'           => %w[create],        # authorize_resource class: false (symbol)
    'attachments'                  => %w[index delete],  # 5.6: authorize! :read/:destroy, Attachment (flag-gated)
    'client_advanced_searches'     => %w[index],         # 5.6: authorize! :read, Client (flag-gated)
    'api/form_builder_attachments' => %w[destroy],       # 5.6: authorize! :update, @attachment.form_buildable (flag-gated)
    'papertrail_queries'           => %w[index],         # 5.6: authorize! :read, DataTracker
    'notifications'                => %w[index],          # 5.6: authorize! :read, Notification
    'enforcement_settings'         => %w[show update]     # Phase 5 capstone: authorize! :manage, EnforcementSetting (in-body before_action + explicit)
  }.freeze

  KNOWN_ORPHAN_CONTROLLERS = %w[able_screens/answer_submissions/clients].freeze

  CANCAN_AUTHORIZE_FILE = 'controller_resource.rb'
  CANCAN_SKIP_FILE      = 'controller_additions.rb'

  def cancan_callback_covers?(klass, action, file_fragment)
    klass._process_action_callbacks.select { |c| c.kind == :before }.any? do |c|
      f = c.filter
      next false unless f.is_a?(Proc) && f.source_location && f.source_location.first.include?(file_fragment)
      callback_applies_to_action?(c, action)
    end
  end

  def callback_applies_to_action?(callback, action)
    action_filters_allow?(callback.instance_variable_get(:@if), action) &&
      action_filters_allow?(callback.instance_variable_get(:@unless), action)
  end

  def action_filters_allow?(filters, action)
    Array(filters).each do |flt|
      next unless flt.is_a?(AbstractController::Callbacks::ActionFilter)
      ck = flt.instance_variable_get(:@conditional_key)
      actions = flt.instance_variable_get(:@actions)
      next unless actions
      included = actions.map(&:to_s).include?(action.to_s)
      return false if ck == :only && !included
      return false if ck == :except && included
    end
    true
  end

  def routed_pairs
    Rails.application.routes.routes.filter_map do |r|
      d = r.defaults
      ctrl = d[:controller].to_s
      act  = d[:action].to_s
      next if ctrl.blank? || act.blank? || ctrl.start_with?('rails/')
      [ctrl, act]
    end.uniq
  end

  it 'every routed + implemented action authorizes (CanCan) or is allowlisted/in-body-authorized' do
    uncovered = []
    missing_controllers = []

    routed_pairs.each do |ctrl, action|
      next if KNOWN_ORPHAN_CONTROLLERS.include?(ctrl)
      klass = "#{ctrl}_controller".camelize.safe_constantize
      if klass.nil?
        missing_controllers << ctrl
        next
      end
      next unless klass.action_methods.include?(action.to_s) # phantom RESTful route from a dead `resources` -- skip
      next if cancan_callback_covers?(klass, action, CANCAN_AUTHORIZE_FILE)
      next if cancan_callback_covers?(klass, action, CANCAN_SKIP_FILE)
      next if Array(IN_BODY_AUTHORIZE[ctrl]).include?(action)
      uncovered << "#{ctrl}##{action}"
    end

    expect(missing_controllers).to be_empty,
      "Routes point at controllers with no class (add to KNOWN_ORPHAN_CONTROLLERS or remove the route): " \
      "#{missing_controllers.uniq.inspect}"

    expect(uncovered).to be_empty,
      "DEFAULT-OPEN actions (neither authorizing nor allowlisted) -- AC-3 violation. Add " \
      "load_and_authorize_resource / authorize! / skip_authorization_check, or IN_BODY_AUTHORIZE with a " \
      "justification: #{uncovered.sort.inspect}"
  end

  it 'enforce_authorization defaults OFF (inert-by-default lock)' do
    expect(Rails.application.config.x.enforce_authorization).to be(false)
  end
end
