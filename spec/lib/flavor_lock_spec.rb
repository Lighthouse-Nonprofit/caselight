# frozen_string_literal: true
require 'rails_helper'
require 'rake'
require Rails.root.join('spec', 'support', 'youth_flavor')

# S1 — everything built for the youth flavor is LOCKED to it:
#   * school routes do not exist at all on a non-youth box (route constraint,
#     evaluated per request — not merely a hidden sidebar entry)
#   * the youth seed rakes refuse to run on another flavor (a hand-run rake
#     can't plant youth taxonomy in a resettlement tenant)
#   * the aeries sync rake is youth-only too
#   * the youth report registry is already flavor-scoped (regression pin)
RSpec.describe 'youth-flavor lock' do
  SCHOOL_PATHS = ['/schools', '/schools/1', '/schools/1/roster', '/schools/1/cohorts',
                  '/schools/1/report_cards', '/schools/1/report_cards/new',
                  '/schools/1/roll_call', '/schools/1/cohorts/2',
                  '/sites', '/sites/1'].freeze

  def recognize(path, method: :get)
    Rails.application.routes.recognize_path(path, method: method)
  end

  context 'on a resettlement box (the default/test posture)' do
    it 'recognizes NO school route' do
      SCHOOL_PATHS.each do |path|
        expect { recognize(path) }.to raise_error(ActionController::RoutingError),
          "#{path} should not route on a resettlement box"
      end
      expect { recognize('/schools/1/report_cards', method: :post) }
        .to raise_error(ActionController::RoutingError)
      expect { recognize('/schools/1/roll_call', method: :post) }
        .to raise_error(ActionController::RoutingError)
    end

    it 'still routes the shared surfaces (no collateral damage)' do
      expect(recognize('/clients')[:controller]).to eq('clients')
      expect(recognize('/agencies')[:controller]).to eq('agencies')
      expect(recognize('/reports')[:controller]).to eq('reports')
    end

    it 'refuses every youth seed rake' do
      Rake.application.rake_require('tasks/youth_taxonomy', [Rails.root.join('lib').to_s])
      Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
      %w[youth:seed_taxonomy youth:seed_programs youth:seed_quantitative youth:seed_domains
         youth:seed_demo_youth youth:seed_schools youth:seed_sites youth:link_schools].each do |name|
        Rake::Task[name].reenable
        expect { silence_stream { Rake::Task[name].invoke } }
          .to raise_error(SystemExit), "#{name} should refuse on a resettlement box"
      end
    end

    it 'refuses the aeries sync rake' do
      Rake.application.rake_require('tasks/aeries', [Rails.root.join('lib').to_s])
      Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
      Rake::Task['aeries:sync'].reenable
      expect { silence_stream { Rake::Task['aeries:sync'].invoke } }.to raise_error(SystemExit)
    end

    it 'exposes no youth reports in the registry' do
      slugs = Reports::Registry.for_flavor('resettlement').map(&:slug)
      expect(slugs).not_to include('youth-served', 'cohort-completion', 'stop-the-hate-quarterly',
                                  'academic-partner', 'sel-outcomes',
                                  'program-session-attendance', 'school-attendance')
      expect { Reports::Registry.find!('stop-the-hate-quarterly', flavor: 'resettlement') }
        .to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  context 'on a youth box' do
    include_context 'youth flavor'

    it 'recognizes every school route' do
      expect(recognize('/schools')[:controller]).to eq('schools')
      expect(recognize('/schools/1/roster')[:action]).to eq('roster')
      expect(recognize('/schools/1/report_cards/new')[:action]).to eq('new_report_cards')
      expect(recognize('/schools/1/cohorts/2')[:action]).to eq('cohort')
      expect(recognize('/schools/1/roll_call', method: :post)[:action]).to eq('create_roll_call')
      expect(recognize('/sites/1')[:action]).to eq('show')
    end
  end

  def silence_stream
    saved = $stdout
    $stdout = StringIO.new
    yield
  ensure
    $stdout = saved
  end
end
