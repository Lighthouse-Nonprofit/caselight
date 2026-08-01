# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# Youth-flavor batch Y1 — the FLAVOR mechanism's contract:
#   * the whitelist is closed and every whitelisted flavor has an overlay dir + a
#     complete FLAVOR_SEEDS entry whose every task actually exists
#   * the active flavor's overlay is on the i18n load path AFTER config/locales
#     (append-last = wins the deep-merge)
#   * test/CI run FLAVOR-unset => resettlement => base rendering byte-identical
RSpec.describe 'FLAVOR mechanism' do
  before(:all) do
    Rake.application.rake_require('tasks/flavor', [Rails.root.join('lib').to_s])
    Rake.application.rake_require('tasks/slo4home_taxonomy', [Rails.root.join('lib').to_s])
    Rake.application.rake_require('tasks/sensitivity_classification', [Rails.root.join('lib').to_s])
    Rake.application.rake_require('tasks/youth_taxonomy', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  it 'defaults to resettlement when FLAVOR is unset (the CI/test posture)' do
    expect(Rails.application.config.x.flavor).to eq('resettlement')
    expect(I18n.t('flavor.name')).to eq('Resettlement')
  end

  it 'whitelists exactly the known flavors, each with an overlay directory' do
    expect(CifWeb::Application::FLAVORS).to match_array(%w[resettlement youth])
    CifWeb::Application::FLAVORS.each do |flavor|
      dir = Rails.root.join('config', 'flavors', flavor)
      expect(Dir.exist?(dir)).to be(true), "missing overlay dir for #{flavor}"
      expect(Dir[dir.join('*.yml').to_s]).not_to be_empty, "no overlay yml for #{flavor}"
    end
  end

  it 'loads the active overlay AFTER every config/locales file (append-last wins)' do
    overlay = Dir[Rails.root.join('config', 'flavors', 'resettlement', '*.yml').to_s].first
    locale_positions = I18n.load_path.each_index.select do |i|
      I18n.load_path[i].to_s.include?('/config/locales/')
    end
    overlay_position = I18n.load_path.index { |p| p.to_s == overlay.to_s }
    expect(overlay_position).not_to be_nil
    expect(overlay_position).to be > locale_positions.max
  end

  it 'every overlay file roots at en: (available_locales is [:en])' do
    CifWeb::Application::FLAVORS.each do |flavor|
      Dir[Rails.root.join('config', 'flavors', flavor, '*.yml').to_s].each do |file|
        expect(YAML.load_file(file).keys).to eq(['en']), "#{file} must root at en:"
      end
    end
  end

  describe 'FLAVOR_SEEDS dispatcher map' do
    it 'covers every whitelisted flavor with seed + demo lists' do
      expect(FLAVOR_SEEDS.keys).to match_array(CifWeb::Application::FLAVORS)
      FLAVOR_SEEDS.each_value do |entry|
        expect(entry).to include(:seed, :demo)
        expect(entry[:seed]).to be_an(Array)
        expect(entry[:demo]).to be_an(Array)
      end
    end

    it 'lists only rake tasks that actually exist' do
      FLAVOR_SEEDS.each do |flavor, entry|
        (entry[:seed] + entry[:demo]).each do |name|
          expect(Rake::Task.task_defined?(name)).to be(true),
            "FLAVOR_SEEDS[#{flavor.inspect}] names unknown task #{name.inspect}"
        end
      end
    end

    it 'keeps resettlement production seeds free of demo tasks (F1)' do
      expect(FLAVOR_SEEDS['resettlement'][:seed]).not_to include('slo4home:seed_demo_family')
      expect(FLAVOR_SEEDS['resettlement'][:demo]).to include('slo4home:seed_demo_family')
    end

    it 'exposes the two bootstrap entry points' do
      expect(Rake::Task.task_defined?('flavor:seed')).to be(true)
      expect(Rake::Task.task_defined?('flavor:seed_demo')).to be(true)
    end
  end

  # Y4 — overlay CONTENT contract. Proven by deep-merging the YAML files in the
  # application.rb load order (base first, overlay last-wins) — the same merge the
  # Simple backend performs, minus its lazy-init (which would pull the GLOBAL
  # load path, i.e. the live resettlement overlay, into any fresh backend).
  describe 'flavor overlay content (Y4)' do
    def flat_keys(hash, prefix = [])
      hash.flat_map do |k, v|
        v.is_a?(Hash) ? flat_keys(v, prefix + [k]) : [(prefix + [k]).join('.')]
      end
    end

    def merged_for(flavor)
      base = YAML.load_file(Rails.root.join('config', 'locales', 'en.yml'))['en']
      Dir[Rails.root.join('config', 'flavors', flavor, '*.yml').to_s].sort.reduce(base) do |acc, file|
        acc.deep_merge(YAML.load_file(file)['en'])
      end
    end

    it 'only overrides base keys or introduces flavor.* (typo guard)' do
      base = flat_keys(YAML.load_file(Rails.root.join('config', 'locales', 'en.yml'))['en'])
      CifWeb::Application::FLAVORS.each do |flavor|
        Dir[Rails.root.join('config', 'flavors', flavor, '*.yml').to_s].each do |file|
          flat_keys(YAML.load_file(file)['en']).each do |key|
            next if key.start_with?('flavor.')
            expect(base).to include(key),
              "#{flavor} overlay key #{key} matches nothing in base en.yml (typo?)"
          end
        end
      end
    end

    it 'youth overlay round-trips: youth vocabulary wins the merge' do
      m = merged_for('youth')
      expect(m.dig('flavor', 'name')).to eq('Youth Development')
      expect(m.dig('dashboards', 'index', 'title')).to eq('Youth Development Dashboard')
      expect(m.dig('dashboards', 'index', 'tile_households')).to eq('FAMILIES')
      expect(m.dig('dashboards', 'index', 'tile_individuals')).to eq('YOUTH')
      expect(m.dig('dashboards', 'index', 'tile_check_ins')).to eq('SERVICE CONTACTS THIS MONTH')
      expect(m.dig('layouts', 'side_menu', 'clients')).to eq('Youth')
      expect(m.dig('layouts', 'side_menu', 'families')).to eq('Families')
      # untouched base keys shine through the overlay
      expect(m.dig('dashboards', 'index', 'tile_programs_offered')).to eq('PROGRAMS OFFERED')
      expect(m.dig('layouts', 'side_menu', 'partners')).to eq('Partners')
    end

    it 'resettlement overlay reclaims only its identity keys' do
      m = merged_for('resettlement')
      expect(m.dig('flavor', 'name')).to eq('Resettlement')
      expect(m.dig('dashboards', 'index', 'title')).to eq('Resettlement Dashboard')
      # everything else stays the neutral base
      expect(m.dig('dashboards', 'index', 'tile_households')).to eq('HOUSEHOLDS')
      expect(m.dig('layouts', 'side_menu', 'clients')).to eq('Individuals')
    end
  end
end
