# frozen_string_literal: true
require 'rails_helper'

# Locks the Bootstrap-5 simple_form wrapper set (POAM-017g). Pre-staged inert in P2; MADE
# LIVE by THE FLIP — default_wrapper/wrapper_mappings now point at the :bs5_* set. This spec
# guards against config drift or a simple_form upgrade breaking the canonical BS5 shapes.
RSpec.describe 'simple_form BS5 wrappers', type: :helper do
  let(:user) { User.new }

  def render_input(**options)
    helper.simple_form_for(user, url: '/probe') { |f| f.input :email, **options }
  end

  it 'THE FLIP: the default wrapper now emits BS5 shapes (mb-3 / form-label), not BS3' do
    html = render_input
    expect(html).to include('mb-3')
    expect(html).to include('form-label')
    expect(html).to include('form-control')
    expect(html).not_to include('form-group')
    expect(html).not_to include('control-label')
  end

  it 'bs5_vertical_form emits the canonical BS5 vertical shape' do
    html = render_input(wrapper: :bs5_vertical_form)
    expect(html).to include('class="mb-3')
    expect(html).to include('form-label')
    expect(html).to include('form-control')
    expect(html).not_to include('form-group')
    expect(html).not_to include('control-label')
    expect(html).not_to include('help-block')
  end

  it 'bs5_vertical_form renders errors as invalid-feedback with is-invalid on the input' do
    user.errors.add(:email, 'is bad')
    html = render_input(wrapper: :bs5_vertical_form)
    expect(html).to include('is-invalid')
    expect(html).to include('invalid-feedback')
    expect(html).not_to include('has-error')
  end

  it 'bs5_vertical_boolean nests input+label inside form-check' do
    html = helper.simple_form_for(user, url: '/probe') do |f|
      f.input :task_notify, as: :boolean, wrapper: :bs5_vertical_boolean
    end
    expect(html).to include('form-check')
    expect(html).to include('form-check-input')
    expect(html).to include('form-check-label')
    expect(html).not_to include('class="checkbox"')
  end

  it 'bs5_horizontal_form uses the BS5 grid (row mb-3 / col-form-label / offset-free col)' do
    html = render_input(wrapper: :bs5_horizontal_form)
    expect(html).to include('row mb-3')
    expect(html).to include('col-form-label')
    expect(html).to include('col-sm-9')
  end

  it 'every bs5_* wrapper is registered' do
    %i[bs5_vertical_form bs5_vertical_file_input bs5_vertical_boolean
       bs5_vertical_radio_and_checkboxes bs5_horizontal_form bs5_horizontal_file_input
       bs5_horizontal_boolean bs5_horizontal_radio_and_checkboxes bs5_inline_form
       bs5_multi_select].each do |name|
      expect(SimpleForm.wrappers.keys).to include(name.to_s),
        "wrapper #{name} missing from SimpleForm.wrappers"
    end
  end
end
