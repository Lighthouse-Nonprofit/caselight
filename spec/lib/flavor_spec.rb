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
end
