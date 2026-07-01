require 'rails_helper'

# Surface D (a11y): the shared action helpers must give every icon-only control an accessible NAME
# (aria-label) and mark the inner glyph decorative (aria-hidden). These render server-side, so a
# helper spec (CI-covered) locks them in. fa_icon (font-awesome-rails 4.7) passes opts through to
# the <i>; both fa_icon-emitted and Rails-tag-emitted aria-* here come out consistently -- the
# assertions use quote-agnostic regexes so they hold regardless of attribute order/quoting.
RSpec.describe 'Accessible icon helpers', type: :helper do
  # These helpers use the relative i18n shortcut t('.are_you_sure'), which needs a template
  # virtual-path that a bare helper spec lacks ("path is not available"). Resolve relative keys
  # to a placeholder and pass ABSOLUTE keys (e.g. shared.actions.delete -> "Delete") through to
  # real I18n, so the aria-label assertions exercise the genuine translation.
  before do
    allow(helper).to receive(:t).and_wrap_original do |orig, key, **opts|
      key.to_s.start_with?('.') ? 'Are you sure?' : orig.call(key, **opts)
    end
  end

  describe '#remove_link' do
    let(:object) { double('record') }
    before do
      allow(helper).to receive(:params).and_return({ locale: 'en' })
      allow(helper).to receive(:url_for).and_return('/x')
    end
    subject(:markup) { helper.remove_link(object, { foo: 0 }) }

    it 'names the delete link with aria-label' do
      expect(markup).to match(/aria-label=["']Delete["']/)
    end
    it 'hides the inner trash icon from screen readers' do
      expect(markup).to match(/fa-trash/)
      expect(markup).to match(/aria-hidden=["']true["']/)
    end
    it 'still renders a delete link (behavior unchanged)' do
      expect(markup).to match(/data-method=["']delete["']|method/)
      expect(markup).to include('fa-trash')
    end
  end

  describe '#delete_button' do
    before { allow(helper).to receive(:params).and_return({ locale: 'en' }) }
    context 'active (no enrollments)' do
      let(:program) { double('program', client_enrollments: double(present?: false)) }
      before { allow(helper).to receive(:program_stream_path).and_return('/program_streams/1') }
      subject(:markup) { helper.delete_button(program) }
      it 'names the delete link and hides the icon' do
        expect(markup).to match(/aria-label=["']Delete["']/)
        expect(markup).to match(/aria-hidden=["']true["']/)
        expect(markup).to include('fa-trash')
      end
    end
    context 'disabled (has enrollments)' do
      let(:program) { double('program', client_enrollments: double(present?: true)) }
      subject(:markup) { helper.delete_button(program) }
      it 'marks the inert div aria-disabled and hides the icon' do
        expect(markup).to match(/aria-disabled=["']true["']/)
        expect(markup).to match(/aria-hidden=["']true["']/)
      end
    end
  end

  describe '#edit_link' do
    let(:client)    { double('client') }
    let(:case_note) { double('case_note') }
    before do
      # `policy` (Pundit's view helper) isn't defined on the bare ActionView::Base, so
      # verify_partial_doubles rejects the stub — bypass verification just for these view stubs.
      without_partial_double_verification do
        allow(helper).to receive(:policy).and_return(double(edit?: true))
        allow(helper).to receive(:edit_client_case_note_path).and_return('/clients/1/case_notes/2/edit')
      end
    end
    subject(:markup) { helper.edit_link(client, case_note) }
    it 'names the edit link and hides the pencil icon' do
      expect(markup).to match(/aria-label=["']Edit["']/)
      expect(markup).to include('fa-pencil')
      expect(markup).to match(/aria-hidden=["']true["']/)
    end
  end
end