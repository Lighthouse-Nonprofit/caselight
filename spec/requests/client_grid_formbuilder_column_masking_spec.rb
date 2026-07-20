# frozen_string_literal: true
require 'rails_helper'

# Phase 5.3 (bypass A) — masking of Datagrid 2.0.9 DYNAMIC custom-field ("formbuilder") columns.
#
# ClientGrid's `dynamic do` block (app/grids/client_grid.rb ~L508-535) renders, per selected
# custom-field column, a grid cell whose VALUE is gated on
#   cf_id.present? && vis_ids.include?(cf_id)
# where vis_ids is the controller-injected `visible_custom_field_ids` (Phase-5.3 SensitivityPolicy
# set; fail-closed to empty). The show page + serializer masking is covered elsewhere; the GRID
# COLUMN path had no coverage — record_cards_security_spec / role_differentiated_index_spec hit
# `get clients_path` WITHOUT selecting a custom-field column, so `next unless dynamic_columns.present?`
# short-circuits and their `not_to include(SENTINEL)` is vacuous for this branch.
#
# ---------------------------------------------------------------------------------------------------
# DISCOVERED (validated via rails runner, RAILS_ENV=test, in-container):
#
# The dynamic formbuilder column WAS broken on Rails 8.1.3 (a datagrid 1.4.4 -> 2.0.9 + Rails 8.0.5 ->
# 8.1.3 regression) and is NOW FIXED — this spec is the regression guard + the live masking contract:
#
#   ClientGrid.new(dynamic_columns: <a formbuilder descriptor>)  # the exact controller call
#     => ArgumentError: wrong number of arguments (given 1, expected 0)
#        at app/grids/client_grid.rb:516  ->  `...parameterize('_')...`
#
# `String#parameterize` in Rails 8.1.3 is keyword-only (`parameterize(separator: "-")`); the positional
# `parameterize('_')` used to build the dynamic column name raises. datagrid 2.0.9 evaluates `dynamic`
# blocks at construction, so the crash happens the moment the controller builds the grid with a
# formbuilder column selected (clients advanced-search index/XLS). The masking branch is therefore
# UNREACHABLE — the path fail-STOPS (500) rather than leaking, so the worst case (a restricted/emergency
# value reaching a strategic_overviewer) is NOT realized today. (ClientGridOptions#form_builder_report,
# the XLS twin, shares the same `parameterize('_')` and the same break.)
#
# Second, independent latent defect (surfaces once the parameterize crash is fixed): the block captures
#   vis_ids = visible_custom_field_ids || Set.new
# as a LOCAL at block-eval (construction) time, but admin_client_grid/non_admin_client_grid inject
# `visible_custom_field_ids=` AFTER construction. So with the controller's ordering the gate sees an
# empty set and OVER-masks admin too. Masking is correct only when the visible set is present at
# construction (verified: admin -> value, strategic_overviewer -> blank, nil -> blank).
#
# THE FIX (this coverage audit): (1) `parameterize('_')` -> `parameterize(separator: '_')` at all five
# sites (the Rails-8.1 keyword form); (2) admin_client_grid/non_admin_client_grid now inject
# `visible_custom_field_ids` INTO ClientGrid.new (at construction) instead of assigning it afterward,
# so the `dynamic do` masking gate closes over the real visible set. The examples below run live: the
# column builds, and the gate masks restricted/emergency values for a strategic_overviewer (fail-closed
# on a nil set) while admin sees them.
RSpec.describe 'ClientGrid dynamic formbuilder column masking (Phase 5.3 bypass A / datagrid 2.0.9)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:admin)      { create(:user, :admin) }
  let(:overviewer) { create(:user, :strategic_overviewer) }

  let!(:client) { create(:client, given_name: 'Cardy', family_name: 'McCardface') }

  # A RESTRICTED custom form filled with a sentinel value; a strategic_overviewer (standard-only) must
  # never see it, admin must. Underscore-free form_title/label so the grid's `id.split('_')` recovers
  # 'Diagnosis' as the properties key (matches production id shape formbuilder_<title>_<label>).
  let!(:restricted_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'FBSpec Restricted',
           sensitivity: 'restricted', fields: [{ 'type' => 'text', 'label' => 'Diagnosis' }])
  end
  let!(:restricted_prop) do
    create(:custom_field_property, custom_field: restricted_cf, custom_formable: client,
           properties: { 'Diagnosis' => 'RESTRICTED_SENTINEL_DO_NOT_LEAK' })
  end

  # An EMERGENCY_ONLY form — masked for EVERY non-admin (no break-glass on the bulk grid path).
  let!(:emergency_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'FBSpec Emergency',
           sensitivity: 'emergency_only', fields: [{ 'type' => 'text', 'label' => 'Whereabouts' }])
  end
  let!(:emergency_prop) do
    create(:custom_field_property, custom_field: emergency_cf, custom_formable: client,
           properties: { 'Whereabouts' => 'EMERGENCY_SENTINEL_DO_NOT_LEAK' })
  end

  # The controller-shaped descriptor array (AdvancedSearches::CustomFields -> FilterTypes) that the
  # clients advanced-search controller merges into ClientGrid.new(dynamic_columns:). Carries the real
  # 2.0.9-era shape incl. custom_field_id (Integer) that the gate keys on.
  def formbuilder_descriptor(custom_field)
    AdvancedSearches::CustomFields.new([custom_field.id]).render
  end

  # Same transform the grid + ClientColumnsVisibility apply to name the dynamic column, in the
  # Rails-8.1 keyword form (the positional form the app still uses is the bug under test).
  def formbuilder_column_name(descriptor)
    descriptor.first[:id].downcase.parameterize(separator: '_').to_sym
  end

  # Render a single dynamic formbuilder cell through the REAL datagrid render path (datagrid/_row uses
  # datagrid_value for html columns), returning the cell HTML string. A leak would surface the sentinel
  # here; a masked cell renders an empty <ul>.
  def render_formbuilder_cell(grid, model)
    controller = ApplicationController.new
    controller.request = ActionDispatch::TestRequest.create
    name = formbuilder_column_name(grid.dynamic_columns)
    controller.view_context.datagrid_value(grid, name, model).to_s
  end

  describe 'the dynamic formbuilder column builds on Rails 8.1.3 (parameterize keyword-form fix)' do
    it 'the formbuilder descriptor is well-formed and building the grid with it no longer raises' do
      descriptor = formbuilder_descriptor(restricted_cf)

      # Non-vacuous: this IS the restricted custom-field column the gate is supposed to mask.
      expect(descriptor.first[:id]).to start_with('formbuilder_')
      expect(descriptor.first[:custom_field_id]).to eq(restricted_cf.id)

      # Regression guard for the datagrid-2.0.9 + Rails-8.1.3 break: the column-name builder used the
      # removed positional `parameterize('_')` (ArgumentError at construction, since datagrid 2.0
      # evaluates `dynamic do` during ClientGrid.new). Fixed to the keyword form; building must not raise.
      expect { ClientGrid.new(dynamic_columns: descriptor) }.not_to raise_error
    end
  end

  describe 'masking contract (Phase 5.3 bypass A)' do
    it 'blanks a RESTRICTED formbuilder cell for a strategic_overviewer while admin sees the value in the same column' do
      descriptor = formbuilder_descriptor(restricted_cf)

      admin_grid = ClientGrid.new(dynamic_columns: descriptor,
                                  visible_custom_field_ids: CustomFieldProperty.visible_custom_field_ids(admin))
      ov_grid    = ClientGrid.new(dynamic_columns: descriptor,
                                  visible_custom_field_ids: CustomFieldProperty.visible_custom_field_ids(overviewer))

      # Non-vacuous baseline: admin (sees all) DOES get the value rendered into the cell.
      expect(render_formbuilder_cell(admin_grid, client)).to include('RESTRICTED_SENTINEL_DO_NOT_LEAK')
      # The masking contract: the strategic_overviewer's cell is blank (value not emitted).
      expect(render_formbuilder_cell(ov_grid, client)).not_to include('RESTRICTED_SENTINEL_DO_NOT_LEAK')
    end

    it 'blanks an EMERGENCY_ONLY formbuilder cell for a strategic_overviewer while admin sees the value' do
      descriptor = formbuilder_descriptor(emergency_cf)

      admin_grid = ClientGrid.new(dynamic_columns: descriptor,
                                  visible_custom_field_ids: CustomFieldProperty.visible_custom_field_ids(admin))
      ov_grid    = ClientGrid.new(dynamic_columns: descriptor,
                                  visible_custom_field_ids: CustomFieldProperty.visible_custom_field_ids(overviewer))

      expect(render_formbuilder_cell(admin_grid, client)).to include('EMERGENCY_SENTINEL_DO_NOT_LEAK')
      expect(render_formbuilder_cell(ov_grid, client)).not_to include('EMERGENCY_SENTINEL_DO_NOT_LEAK')
    end

    it 'fails closed: an absent (nil) visible_custom_field_ids blanks the cell rather than rendering the value' do
      descriptor = formbuilder_descriptor(restricted_cf)

      # No visible set injected: the gate (vis_ids || Set.new) must over-mask, never leak.
      no_vis_grid = ClientGrid.new(dynamic_columns: descriptor)
      # Non-vacuous: with the visible set the same cell WOULD render the value.
      with_vis_grid = ClientGrid.new(dynamic_columns: descriptor,
                                     visible_custom_field_ids: CustomFieldProperty.visible_custom_field_ids(admin))

      expect(render_formbuilder_cell(no_vis_grid, client)).not_to include('RESTRICTED_SENTINEL_DO_NOT_LEAK')
      expect(render_formbuilder_cell(with_vis_grid, client)).to include('RESTRICTED_SENTINEL_DO_NOT_LEAK')
    end
  end
end
