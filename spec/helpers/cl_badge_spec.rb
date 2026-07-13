# frozen_string_literal: true
require 'rails_helper'

# cl_badge is the BS5 chokepoint (POAM-017g): every colored status pill in the app renders
# through it. THE FLIP switched it from BS3 'label label-*' to BS5 'badge text-bg-*' (with the
# 'default' variant mapping to 'text-bg-light', since BS5 has no text-bg-default). These
# examples pin BOTH halves of the contract: the variant allowlist (model data can never reach
# the class attribute) and the BS5 output shape.
RSpec.describe ApplicationHelper, type: :helper do
  describe '#cl_badge' do
    it 'renders a span with the BS5 badge classes for an allowlisted variant' do
      expect(helper.cl_badge('Active', :primary))
        .to eq('<span class="badge text-bg-primary">Active</span>')
    end

    it 'accepts string variants and every allowlisted value' do
      ApplicationHelper::CL_BADGE_VARIANTS.each do |variant|
        expected = ApplicationHelper::CL_BADGE_BS5.fetch(variant, variant)
        expect(helper.cl_badge('x', variant)).to include("text-bg-#{expected}")
      end
    end

    it 'falls back to the default variant (text-bg-light) for anything off-allowlist (injection guard)' do
      expect(helper.cl_badge('x', 'danger" onmouseover="alert(1)'))
        .to eq('<span class="badge text-bg-light">x</span>')
      expect(helper.cl_badge('x', nil))
        .to eq('<span class="badge text-bg-light">x</span>')
    end

    it 'escapes the text' do
      expect(helper.cl_badge('<b>hi</b>', :info)).to include('&lt;b&gt;hi&lt;/b&gt;')
    end

    it 'supports a block-level tag for the enrollment status partials' do
      expect(helper.cl_badge('Exited', :danger, tag: :div))
        .to eq('<div class="badge text-bg-danger">Exited</div>')
    end
  end

  describe '#status_style' do
    it 'routes through cl_badge with the status-specific variant' do
      expect(helper.status_style('Referred')).to eq('<span class="badge text-bg-danger">Referred</span>')
      expect(helper.status_style('Investigating')).to include('text-bg-warning')
      expect(helper.status_style('Accepted')).to include('text-bg-primary')
    end
  end
end
