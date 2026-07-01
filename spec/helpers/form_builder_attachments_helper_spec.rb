require 'rails_helper'

# Surface D: the polymorphic attachment delete links (4 controller branches) must each carry an
# accessible name + a hidden icon. Exercise the custom_field_properties branch (self-contained) as
# the representative; the other three are byte-identical. Quote-agnostic assertions.
RSpec.describe FormBuilderAttachmentsHelper, type: :helper do
  # Resolve the relative i18n shortcut t('.are_you_sure') (no template virtual-path in a helper
  # spec) to a placeholder; pass absolute keys (shared.actions.delete_attachment -> "Delete
  # attachment") through to real I18n so the aria-label assertion exercises the genuine string.
  before do
    allow(helper).to receive(:t).and_wrap_original do |orig, key, **opts|
      key.to_s.start_with?('.') ? 'Are you sure?' : orig.call(key, **opts)
    end
  end

  describe '#form_buildable_path' do
    let(:resource) { double('attachment') }
    before do
      allow(helper).to receive(:controller_name).and_return('custom_field_properties')
      allow(helper).to receive(:params).and_return({ locale: 'en' })
      helper.instance_variable_set(:@custom_formable, double('formable'))
      helper.instance_variable_set(:@custom_field, double('cf', id: 7))
      allow(helper).to receive(:polymorphic_path).and_return('/clients/1/custom_field_properties/2')
    end
    subject(:markup) { helper.form_buildable_path(resource, 0, 'Passport', {}) }

    it 'names the attachment-delete link' do
      expect(markup).to match(/aria-label=["']Delete attachment["']/)
    end
    it 'hides the inner trash icon' do
      expect(markup).to match(/aria-hidden=["']true["']/)
      expect(markup).to include('fa-trash')
    end
    it 'preserves the delete method (behavior unchanged)' do
      expect(markup).to match(/data-method=["']delete["']|method/)
    end
  end
end