# frozen_string_literal: true
require 'rails_helper'

# Section 508 / WCAG 2.1 AA table-semantics regression guard for surface B.
# View specs render the VENDORED datagrid partials (app/views/datagrid/*) through the
# real datagrid-1.4.4 gem code path, exactly as production does. NOTE: this is a
# spec/views spec; confirm the CI job includes spec/views (see verification_steps). If
# spec/views is NOT in the CI subset, the surface-B enforcement falls to the request
# spec clients_index_caption_a11y_spec.rb below (which IS in spec/requests). A minimal
# in-spec grid keeps the test hermetic: its scope returns an empty relation (.none) so
# no DB rows / tenant / login are needed; headers still render (html_columns derives
# from column declarations, not data).
# A minimal REAL grid constant (not stub_const — rspec-mocks doubles/stubs are not permitted
# outside the per-example lifecycle, and this needs to exist at load time for the view partials).
# Its scope is .none so no DB rows / tenant / login are needed; headers render from the column
# declarations, not data.
class A11yProbeGrid
  include Datagrid
  scope { User.none }
  column(:name,  header: -> { 'Name' })
  column(:email, header: -> { 'Email' })
end

RSpec.describe 'datagrid accessibility (surface B)', type: :view do
  let(:grid) { A11yProbeGrid.new }

  before do
    admin = double('User', admin?: true)
    allow(view).to receive(:current_user).and_return(admin)
  end

  describe 'datagrid/_head (column header <th> scope)' do
    it 'renders every column header cell with scope="col"' do
      render partial: 'datagrid/head',
             locals: { grid: grid, options: { columns: [], order: false } }
      expect(rendered.scan(/scope=["']col["']/).length).to eq(2)
      expect(rendered).to include('<th')
    end

    it 'preserves the existing title attribute alongside scope' do
      render partial: 'datagrid/head',
             locals: { grid: grid, options: { columns: [], order: false } }
      expect(rendered).to match(/title=["']Name["']/)
      expect(rendered).to match(/title=["']Email["']/)
    end
  end

  describe 'datagrid/_table (shared caption for the 9 datagrid_table sites)' do
    it 'renders a caption as the first child of the table' do
      render partial: 'datagrid/table',
             locals: { grid: grid, assets: grid.assets,
                       options: { columns: [], html: {}, order: false } }
      expect(rendered).to include('<caption')
      expect(rendered.index('<caption')).to be < rendered.index('<thead')
    end

    it 'uses the caller-supplied :caption option when present' do
      render partial: 'datagrid/table',
             locals: { grid: grid, assets: grid.assets,
                       options: { columns: [], html: {}, order: false, caption: 'Families' } }
      expect(rendered).to include('Families')
    end

    it 'falls back to the humanized grid class name when no :caption is given' do
      render partial: 'datagrid/table',
             locals: { grid: grid, assets: grid.assets,
                       options: { columns: [], html: {}, order: false } }
      expect(rendered).to include('A11y probe grid')
    end

    it 'hides the caption visually via the sr-only class (no layout change)' do
      render partial: 'datagrid/table',
             locals: { grid: grid, assets: grid.assets,
                       options: { columns: [], html: {}, order: false } }
      expect(rendered).to match(/<caption[^>]*class=["'][^"']*sr-only/)
    end

    it 'still emits scope="col" headers through the shared table path' do
      render partial: 'datagrid/table',
             locals: { grid: grid, assets: grid.assets,
                       options: { columns: [], html: {}, order: false } }
      expect(rendered).to match(/scope=["']col["']/)
    end
  end
end