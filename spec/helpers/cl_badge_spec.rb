# frozen_string_literal: true
require 'rails_helper'

# cl_badge is the BS5-prep chokepoint (POAM-017g P1): every colored status pill in the app
# renders through it, so the BS3 'label label-*' -> BS5 'badge text-bg-*' rename is a
# one-method flip at the cutover. These examples pin BOTH halves of the contract: the
# variant allowlist (model data can never reach the class attribute) and the current BS3
# output shape (the flip PR updates the expected classes here deliberately, in the same
# commit as the helper).
RSpec.describe ApplicationHelper, type: :helper do
  describe '#cl_badge' do
    it 'renders a span with the BS3 label classes for an allowlisted variant' do
      expect(helper.cl_badge('Active', :primary))
        .to eq('<span class="label label-primary">Active</span>')
    end

    it 'accepts string variants and every allowlisted value' do
      ApplicationHelper::CL_BADGE_VARIANTS.each do |variant|
        expect(helper.cl_badge('x', variant)).to include("label-#{variant}")
      end
    end

    it 'falls back to the default variant for anything off-allowlist (injection guard)' do
      expect(helper.cl_badge('x', 'danger" onmouseover="alert(1)'))
        .to eq('<span class="label label-default">x</span>')
      expect(helper.cl_badge('x', nil))
        .to eq('<span class="label label-default">x</span>')
    end

    it 'escapes the text' do
      expect(helper.cl_badge('<b>hi</b>', :info)).to include('&lt;b&gt;hi&lt;/b&gt;')
    end

    it 'supports a block-level tag for the enrollment status partials' do
      expect(helper.cl_badge('Exited', :danger, tag: :div))
        .to eq('<div class="label label-danger">Exited</div>')
    end
  end

  describe '#status_style' do
    it 'routes through cl_badge with the status-specific variant' do
      expect(helper.status_style('Referred')).to eq('<span class="label label-danger">Referred</span>')
      expect(helper.status_style('Investigating')).to include('label-warning')
      expect(helper.status_style('Accepted')).to include('label-primary')
    end
  end
end
