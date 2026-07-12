# Use this setup block to configure all options available in SimpleForm.
SimpleForm.setup do |config|
  config.error_notification_class = 'alert alert-danger'
  config.button_class = 'btn btn-primary' # POAM-017g flip: btn-default no longer exists in BS5
  config.boolean_label_class = nil

  config.wrappers :vertical_form, tag: 'div', class: 'form-group', error_class: 'has-error' do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly
    b.use :label, class: 'control-label'

    b.use :input, class: 'form-control'
    b.use :error, wrap_with: { tag: 'span', class: 'help-block' }
    b.use :hint,  wrap_with: { tag: 'p', class: 'help-block' }
  end

  config.wrappers :vertical_file_input, tag: 'div', class: 'form-group', error_class: 'has-error' do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :readonly
    b.use :label, class: 'control-label'

    b.use :input
    b.use :error, wrap_with: { tag: 'span', class: 'help-block' }
    b.use :hint,  wrap_with: { tag: 'p', class: 'help-block' }
  end

  config.wrappers :vertical_boolean, tag: 'div', class: 'form-group', error_class: 'has-error' do |b|
    b.use :html5
    b.optional :readonly

    b.wrapper tag: 'div', class: 'checkbox' do |ba|
      ba.use :label_input
    end

    b.use :error, wrap_with: { tag: 'span', class: 'help-block' }
    b.use :hint,  wrap_with: { tag: 'p', class: 'help-block' }
  end

  config.wrappers :vertical_radio_and_checkboxes, tag: 'div', class: 'form-group', error_class: 'has-error' do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: 'control-label'
    b.use :input
    b.use :error, wrap_with: { tag: 'span', class: 'help-block' }
    b.use :hint,  wrap_with: { tag: 'p', class: 'help-block' }
  end

  config.wrappers :horizontal_form, tag: 'div', class: 'form-group', error_class: 'has-error' do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly
    b.use :label, class: 'col-sm-3 control-label'

    b.wrapper tag: 'div', class: 'col-sm-9' do |ba|
      ba.use :input, class: 'form-control'
      ba.use :error, wrap_with: { tag: 'span', class: 'help-block' }
      ba.use :hint,  wrap_with: { tag: 'p', class: 'help-block' }
    end
  end

  config.wrappers :horizontal_file_input, tag: 'div', class: 'form-group', error_class: 'has-error' do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :readonly
    b.use :label, class: 'col-sm-3 control-label'

    b.wrapper tag: 'div', class: 'col-sm-9' do |ba|
      ba.use :input
      ba.use :error, wrap_with: { tag: 'span', class: 'help-block' }
      ba.use :hint,  wrap_with: { tag: 'p', class: 'help-block' }
    end
  end

  config.wrappers :horizontal_boolean, tag: 'div', class: 'form-group', error_class: 'has-error' do |b|
    b.use :html5
    b.optional :readonly

    b.wrapper tag: 'div', class: 'col-sm-offset-3 col-sm-9' do |wr|
      wr.wrapper tag: 'div', class: 'checkbox' do |ba|
        ba.use :label_input
      end

      wr.use :error, wrap_with: { tag: 'span', class: 'help-block' }
      wr.use :hint,  wrap_with: { tag: 'p', class: 'help-block' }
    end
  end

  config.wrappers :horizontal_radio_and_checkboxes, tag: 'div', class: 'form-group', error_class: 'has-error' do |b|
    b.use :html5
    b.optional :readonly

    b.use :label, class: 'col-sm-3 control-label'

    b.wrapper tag: 'div', class: 'col-sm-9' do |ba|
      ba.use :input
      ba.use :error, wrap_with: { tag: 'span', class: 'help-block' }
      ba.use :hint,  wrap_with: { tag: 'p', class: 'help-block' }
    end
  end

  config.wrappers :inline_form, tag: 'div', class: 'form-group', error_class: 'has-error' do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly
    b.use :label, class: 'sr-only'

    b.use :input, class: 'form-control'
    b.use :error, wrap_with: { tag: 'span', class: 'help-block' }
    b.use :hint,  wrap_with: { tag: 'p', class: 'help-block' }
  end

  config.wrappers :multi_select, tag: 'div', class: 'form-group', error_class: 'has-error' do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: 'control-label'
    b.wrapper tag: 'div', class: 'form-inline' do |ba|
      ba.use :input, class: 'form-control'
      ba.use :error, wrap_with: { tag: 'span', class: 'help-block' }
      ba.use :hint,  wrap_with: { tag: 'p', class: 'help-block' }
    end
  end
  # ---------------------------------------------------------------------------
  # Bootstrap 5 wrapper set (POAM-017g). Pre-staged inert in P2; MADE LIVE by THE
  # FLIP (default_wrapper/wrapper_mappings at the bottom of this file now point
  # here). Shapes follow the canonical simple_form Bootstrap-5 template: mb-3
  # wrapper, form-label, is-invalid / invalid-feedback (d-block where the input is
  # not the feedback's sibling), form-text hints, form-check booleans/collections.
  # The BS3 wrapper set above is retained only as a fallback reference and is no
  # longer mapped to anything.
  # ---------------------------------------------------------------------------
  config.wrappers :bs5_vertical_form, tag: 'div', class: 'mb-3' do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly
    b.use :label, class: 'form-label'
    b.use :input, class: 'form-control', error_class: 'is-invalid', valid_class: 'is-valid'
    b.use :error, wrap_with: { tag: 'div', class: 'invalid-feedback' }
    b.use :hint,  wrap_with: { tag: 'div', class: 'form-text' }
  end

  config.wrappers :bs5_vertical_file_input, tag: 'div', class: 'mb-3' do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :readonly
    b.use :label, class: 'form-label'
    b.use :input, class: 'form-control', error_class: 'is-invalid', valid_class: 'is-valid'
    b.use :error, wrap_with: { tag: 'div', class: 'invalid-feedback' }
    b.use :hint,  wrap_with: { tag: 'div', class: 'form-text' }
  end

  config.wrappers :bs5_vertical_boolean, tag: 'div', class: 'mb-3' do |b|
    b.use :html5
    b.optional :readonly
    b.wrapper tag: 'div', class: 'form-check' do |ba|
      ba.use :input, class: 'form-check-input', error_class: 'is-invalid', valid_class: 'is-valid'
      ba.use :label, class: 'form-check-label'
      ba.use :error, wrap_with: { tag: 'div', class: 'invalid-feedback d-block' }
      ba.use :hint,  wrap_with: { tag: 'div', class: 'form-text' }
    end
  end

  config.wrappers :bs5_vertical_radio_and_checkboxes, tag: 'fieldset', class: 'mb-3',
                  item_wrapper_class: 'form-check', item_label_class: 'form-check-label' do |b|
    b.use :html5
    b.optional :readonly
    b.wrapper :legend_tag, tag: 'legend', class: 'col-form-label pt-0' do |ba|
      ba.use :label_text
    end
    b.use :input, class: 'form-check-input', error_class: 'is-invalid', valid_class: 'is-valid'
    b.use :full_error, wrap_with: { tag: 'div', class: 'invalid-feedback d-block' }
    b.use :hint, wrap_with: { tag: 'div', class: 'form-text' }
  end

  config.wrappers :bs5_horizontal_form, tag: 'div', class: 'row mb-3' do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly
    b.use :label, class: 'col-sm-3 col-form-label'
    b.wrapper tag: 'div', class: 'col-sm-9' do |ba|
      ba.use :input, class: 'form-control', error_class: 'is-invalid', valid_class: 'is-valid'
      ba.use :error, wrap_with: { tag: 'div', class: 'invalid-feedback' }
      ba.use :hint,  wrap_with: { tag: 'div', class: 'form-text' }
    end
  end

  config.wrappers :bs5_horizontal_file_input, tag: 'div', class: 'row mb-3' do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :readonly
    b.use :label, class: 'col-sm-3 col-form-label'
    b.wrapper tag: 'div', class: 'col-sm-9' do |ba|
      ba.use :input, class: 'form-control', error_class: 'is-invalid', valid_class: 'is-valid'
      ba.use :error, wrap_with: { tag: 'div', class: 'invalid-feedback' }
      ba.use :hint,  wrap_with: { tag: 'div', class: 'form-text' }
    end
  end

  config.wrappers :bs5_horizontal_boolean, tag: 'div', class: 'row mb-3' do |b|
    b.use :html5
    b.optional :readonly
    b.wrapper tag: 'div', class: 'col-sm-9 offset-sm-3' do |wr|
      wr.wrapper tag: 'div', class: 'form-check' do |ba|
        ba.use :input, class: 'form-check-input', error_class: 'is-invalid', valid_class: 'is-valid'
        ba.use :label, class: 'form-check-label'
        ba.use :error, wrap_with: { tag: 'div', class: 'invalid-feedback d-block' }
        ba.use :hint,  wrap_with: { tag: 'div', class: 'form-text' }
      end
    end
  end

  config.wrappers :bs5_horizontal_radio_and_checkboxes, tag: 'div', class: 'row mb-3',
                  item_wrapper_class: 'form-check', item_label_class: 'form-check-label' do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: 'col-sm-3 col-form-label pt-0'
    b.wrapper tag: 'div', class: 'col-sm-9' do |ba|
      ba.use :input, class: 'form-check-input', error_class: 'is-invalid', valid_class: 'is-valid'
      ba.use :full_error, wrap_with: { tag: 'div', class: 'invalid-feedback d-block' }
      ba.use :hint, wrap_with: { tag: 'div', class: 'form-text' }
    end
  end

  config.wrappers :bs5_inline_form, tag: 'div', class: 'col-12' do |b|
    b.use :html5
    b.use :placeholder
    b.optional :maxlength
    b.optional :pattern
    b.optional :min_max
    b.optional :readonly
    b.use :label, class: 'visually-hidden'
    b.use :input, class: 'form-control', error_class: 'is-invalid', valid_class: 'is-valid'
    b.use :error, wrap_with: { tag: 'div', class: 'invalid-feedback' }
    b.use :hint,  wrap_with: { tag: 'div', class: 'form-text' }
  end

  config.wrappers :bs5_multi_select, tag: 'div', class: 'mb-3' do |b|
    b.use :html5
    b.optional :readonly
    b.use :label, class: 'form-label'
    b.wrapper tag: 'div', class: 'd-flex flex-row gap-2 align-items-center' do |ba|
      ba.use :input, class: 'form-select', error_class: 'is-invalid', valid_class: 'is-valid'
      ba.use :error, wrap_with: { tag: 'div', class: 'invalid-feedback d-block' }
      ba.use :hint,  wrap_with: { tag: 'div', class: 'form-text' }
    end
  end

  # Wrappers for forms and inputs using the Bootstrap toolkit.
  # Check the Bootstrap docs (http://getbootstrap.com)
  # to learn about the different styles for forms and inputs,
  # buttons and other elements.
  # POAM-017g THE FLIP: default + mappings point at the BS5 wrapper set (was the
  # :vertical_*/:multi_select BS3 set above).
  config.default_wrapper = :bs5_vertical_form
  config.wrapper_mappings = {
    check_boxes: :bs5_vertical_radio_and_checkboxes,
    radio_buttons: :bs5_vertical_radio_and_checkboxes,
    file: :bs5_vertical_file_input,
    boolean: :bs5_vertical_boolean,
    datetime: :bs5_multi_select,
    date: :bs5_multi_select,
    time: :bs5_multi_select
  }
end
