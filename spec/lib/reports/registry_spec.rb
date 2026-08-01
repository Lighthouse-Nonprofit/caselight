# frozen_string_literal: true
require 'rails_helper'

# Reports batch — the registry contract (fail-loud, mirrors flavor_spec):
# every registered definition must resolve its class, carry base i18n, declare a
# known tier and known period presets; slugs unique per flavor; find! is
# flavor-scoped (wrong-flavor slug = RecordNotFound = 404).
RSpec.describe Reports::Registry do
  Reports::Registry::REGISTRY.each do |flavor, definitions|
    context "#{flavor} registry" do
      it 'has unique slugs' do
        expect(definitions.map(&:slug)).to eq(definitions.map(&:slug).uniq)
      end

      it 'every definition resolves class, tier, presets, and base i18n' do
        definitions.each do |definition|
          expect { definition.klass }.not_to raise_error
          expect(definition.klass.ancestors).to include(Reports::BaseReport)
          expect(Reports::Registry::TIER_ORDER).to include(definition.audience),
            "#{definition.slug}: unknown audience #{definition.audience}"
          expect(definition.presets - Reports::Period::PRESETS).to be_empty,
            "#{definition.slug}: unknown presets #{(definition.presets - Reports::Period::PRESETS).inspect}"
          %w[title description].each do |key|
            expect(I18n.exists?("reports.registry.#{definition.i18n_key}.#{key}")).to be(true),
              "#{definition.slug}: missing base i18n reports.registry.#{definition.i18n_key}.#{key}"
          end
        end
      end
    end
  end

  it 'find! searches only the active flavor (youth slug 404s on resettlement)' do
    expect { described_class.find!('youth-served', flavor: 'resettlement') }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(described_class.find!('youth-served', flavor: 'youth').slug).to eq('youth-served')
  end

  describe '.visible_to' do
    it 'filters by the tier abilities a role holds' do
      admin = Ability.new(create(:user, :admin))
      worker = Ability.new(create(:user, roles: 'case worker'))
      expect(described_class.visible_to(admin, flavor: 'resettlement').map(&:slug))
        .to include('served-summary', 'my-caseload-progress')
      worker_slugs = described_class.visible_to(worker, flavor: 'resettlement').map(&:slug)
      expect(worker_slugs).to include('my-caseload-progress', 'my-follow-up-compliance')
      expect(worker_slugs).not_to include('served-summary')
    end
  end
end
