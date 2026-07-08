# frozen_string_literal: true
require 'rails_helper'

# Regression guard for the live DataTrackers#index 500 (Psych::DisallowedClass:
# "Tried to load unspecified class: ActiveSupport::TimeWithZone") hit on the pre-Phase-6 box.
#
# paper_trail's YAML serializer deserializes versions.object through
# ActiveRecord.yaml_column_permitted_classes. Without the data classes on that list (the Rails
# default is effectively [Symbol] when the app does not call config.load_defaults), `version.reify`
# — used by shared/version_type/_common.haml:30 + _client.haml on the delete-event branch, reached
# from data_trackers#index — raises on any version whose object carries a Date/Time/TimeWithZone.
#
# The fix lives in config/application.rb (config.active_record.yaml_column_permitted_classes, added
# Phase 6 U2). This spec fails if that config is removed/narrowed, so the box 500 cannot return.
RSpec.describe 'PaperTrail version reify — YAML permitted classes (DataTrackers#index guard)', type: :model do
  it 'permits the data classes a version payload carries' do
    permitted = ActiveRecord.yaml_column_permitted_classes
    [Date, Time, ActiveSupport::TimeWithZone, ActiveSupport::HashWithIndifferentAccess].each do |klass|
      expect(permitted).to include(klass), "ActiveRecord.yaml_column_permitted_classes must include #{klass} " \
        "or version.reify 500s on DataTrackers#index (Psych::DisallowedClass)"
    end
  end

  it 'reifies a delete-event version whose object contains an ActiveSupport::TimeWithZone' do
    # Plant the exact shape the box choked on: a serialized object with a TimeWithZone value.
    version = PaperTrail::Version.create!(
      item_type: 'Client', item_id: 987_654, event: 'destroy', whodunnit: 'spec'
    )
    version.update_columns(
      object: YAML.dump('id' => 987_654, 'slug' => 'reify-guard', 'created_at' => Time.zone.now)
    )

    expect { version.reify }.not_to raise_error
    reified = version.reify
    expect(reified).to be_a(Client)
    expect(reified.slug).to eq('reify-guard')
  ensure
    PaperTrail::Version.where(item_id: 987_654).delete_all
  end
end
