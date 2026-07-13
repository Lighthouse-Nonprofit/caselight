CIF.CustomFormBuilder = class CustomFormBuilder {
  constructor() {}

  // Shared formBuilder 3.x options (R12B) — the four init sites (custom-field form/show,
  // program-stream enrollment/tracking/exit) pass {formData, sticky} and get everything
  // else from here. i18n: mi18n ALWAYS fetches <location><locale>.lang at init (its
  // addLanguage never marks the locale loaded), so location points at the vendored copy
  // in public/fb-lang/ — absolute path, else it resolves relative to the page URL and
  // 404s on every builder page. en-US strings are also compiled into the dist, so a
  // failed fetch degrades gracefully; hosting the file just keeps the console clean.
  builderOptions({ formData = '', sticky = false } = {}) {
    const options = {
      dataType: 'json',
      formData,
      disableFields: ['autocomplete', 'header', 'hidden', 'paragraph', 'button', 'checkbox'],
      showActionButtons: false,
      i18n: {
        locale: 'en-US',
        location: '/fb-lang/',
        override: {
          'en-US': { cannotBeEmpty: 'name_separated_with_underscore' },
        },
      },
      typeUserEvents: {
        'checkbox-group': this.eventCheckboxOption(),
        date: this.eventDateOption(),
        file: this.eventFileOption(),
        number: this.eventNumberOption(),
        'radio-group': this.eventRadioOption(),
        select: this.eventSelectOption(),
        text: this.eventTextFieldOption(),
        textarea: this.eventTextAreaOption(),
      },
    };
    if (sticky) {
      options.stickyControls = {
        enable: true,
        offset: { top: 20, right: 20, left: 'auto' },
      };
    }
    return options;
  }

  eventCheckboxOption() {
    const self = this;
    return {
      onadd(fld) {
        $('.other-wrap, .className-wrap, .access-wrap, .description-wrap, .name-wrap').hide();
        self.handleCheckingForm();
        self.hideOptionValue();
        self.addOptionCallback(fld);
        return self.generateValueForSelectOption(fld);
      },
      onclone(fld) {
        return setTimeout(function () {
          self.handleCheckingForm();
          self.hideOptionValue();
          self.addOptionCallback(fld);
          return self.generateValueForSelectOption(fld);
        }, 50);
      },
    };
  }

  eventDateOption() {
    const self = this;
    return {
      onadd(fld) {
        $('.className-wrap, .value-wrap, .access-wrap, .description-wrap, .name-wrap').hide();
        return self.handleCheckingForm();
      },
      onclone(fld) {
        return setTimeout(() => self.handleCheckingForm(), 50);
      },
    };
  }

  eventFileOption() {
    const self = this;
    return {
      onadd(fld) {
        $('.className-wrap, .value-wrap, .access-wrap, .description-wrap, .name-wrap').hide();
        return self.handleCheckingForm();
      },
      onclone(fld) {
        return setTimeout(() => self.handleCheckingForm(), 50);
      },
    };
  }

  eventNumberOption() {
    const self = this;
    return {
      onadd(fld) {
        $(
          '.className-wrap, .value-wrap, .step-wrap, .access-wrap, .description-wrap, .name-wrap',
        ).hide();
        return self.handleCheckingForm();
      },
      onclone(fld) {
        return setTimeout(() => self.handleCheckingForm(), 50);
      },
    };
  }

  eventRadioOption() {
    const self = this;
    return {
      onadd(fld) {
        $('.other-wrap, .className-wrap, .access-wrap, .description-wrap, .name-wrap').hide();
        self.handleCheckingForm();
        self.hideOptionValue();
        self.addOptionCallback(fld);
        return self.generateValueForSelectOption(fld);
      },
      onclone(fld) {
        return setTimeout(function () {
          self.handleCheckingForm();
          self.hideOptionValue();
          self.addOptionCallback(fld);
          return self.generateValueForSelectOption(fld);
        }, 50);
      },
    };
  }

  eventSelectOption() {
    const self = this;
    return {
      onadd(fld) {
        $('.className-wrap, .access-wrap, .description-wrap, .name-wrap').hide();
        self.handleCheckingForm();
        self.hideOptionValue();
        self.addOptionCallback(fld);
        return self.generateValueForSelectOption(fld);
      },
      onclone(fld) {
        return setTimeout(function () {
          self.handleCheckingForm();
          self.hideOptionValue();
          self.addOptionCallback(fld);
          return self.generateValueForSelectOption(fld);
        }, 50);
      },
    };
  }

  eventTextFieldOption() {
    const self = this;
    return {
      onadd(fld) {
        $('.fld-subtype ').find('option:contains(color)').remove();
        $('.fld-subtype ').find('option:contains(tel)').remove();
        $('.fld-subtype ').find('option:contains(password)').remove();
        $(
          '.className-wrap, .value-wrap, .access-wrap, .maxlength-wrap, .description-wrap, .name-wrap',
        ).hide();
        return self.handleCheckingForm();
      },
      onclone(fld) {
        return setTimeout(() => self.handleCheckingForm(), 50);
      },
    };
  }

  eventTextAreaOption() {
    const self = this;
    return {
      onadd(fld) {
        // SECURITY (R12B): formBuilder 3.x offers tinymce/quill textarea SUBTYPES whose
        // builder preview loads the editor FROM A CDN at runtime when it isn't on the page
        // (cdnjs script injection) — that would reintroduce the retired TinyMCE (POAM-017a)
        // via an unpinned third-party script and violate the CSP once enforced. Strip them
        // from the subtype dropdown, same pattern as the text field's color/tel/password.
        $('.fld-subtype ').find('option:contains(tinymce)').remove();
        $('.fld-subtype ').find('option:contains(quill)').remove();
        $(
          '.rows-wrap, .className-wrap, .value-wrap, .access-wrap, .maxlength-wrap, .description-wrap, .name-wrap',
        ).hide();
        return self.handleCheckingForm();
      },
      onclone(fld) {
        return setTimeout(() => self.handleCheckingForm(), 50);
      },
    };
  }

  hideOptionValue() {
    return $('.option-selected, .option-value').hide();
  }

  addOptionCallback(field) {
    return $('.add-opt').on('click', () =>
      setTimeout(() => $(field).find('.option-selected, .option-value').hide()),
    );
  }
  generateValueForSelectOption(field) {
    return $(field)
      .find('input.option-label')
      .on('keyup change', function () {
        const value = $(this).val();
        return $(this).siblings('.option-value').val(value);
      });
  }

  handleCheckingForm() {
    this.handleDisplayDuplicateWarning();
    this.actionRemoveField();
    return this.actionEditField();
  }

  getDuplicateValues(elements) {
    const self = this;
    return $(elements).each(function (index, label) {
      const displayText = $(label).text();
      return $(elements).each(function (cIndex, cLabel) {
        if (cIndex === index) {
          return;
        }
        const cText = $(cLabel).text();
        if (cText === displayText) {
          return self.addDuplicateWarning(label);
        }
      });
    });
  }

  handleDisplayDuplicateWarning() {
    if ($('#trackings').is(':visible') && $('.nested-fields').is(':visible')) {
      const elementFrmbs = $('ul.frmb:visible');
      return (() => {
        const result = [];
        for (var element of elementFrmbs) {
          var elements = $(element).find('.field-label:visible');
          result.push(this.getDuplicateValues(elements));
        }
        return result;
      })();
    } else {
      const elements = $('ul.frmb:visible .field-label:visible');
      return this.getDuplicateValues(elements);
    }
  }

  addDuplicateWarning(element) {
    const errorText =
      'Field labels must be unique, please click the edit icon to set a unique field label';
    const parentElement = $(element).parents('li.form-field');
    $(parentElement).addClass('has-error');
    $(parentElement).find('input, textarea, select').addClass('error');
    if (!$(parentElement).find('label.error').is(':visible')) {
      $(parentElement).append(`<label class='error'>${errorText}</label>`);
      if ($('#custom-field-submit').length) {
        return $('#custom-field-submit').attr('disabled', 'true');
      }
    }
  }

  actionRemoveField() {
    const self = this;
    return $('.field-actions a.del-button').click(() =>
      setTimeout(() => self.removeFieldDuplicate(), 300),
    );
  }

  actionEditField() {
    const self = this;
    const labels = $('.field-label:visible');
    // formBuilder 3.x: the edit toggle is a.toggle-form (1.x used a.icon-pencil, gone),
    // and the label editor in the edit card is the .fld-label control (1.x rendered
    // input[name='label'] inside .form-elements). Bind both label forms defensively —
    // 3.x renders label editing as a contenteditable in some builds ('input' covers it).
    return $('.field-actions a.toggle-form').click(() =>
      $('.form-elements .fld-label, .form-elements input[name="label"]').on('change input', () =>
        setTimeout(function () {
          self.removeFieldDuplicate();
          return self.handleDisplayDuplicateWarning(labels);
        }, 300),
      ),
    );
  }

  getNoneDuplicateLabel(elements) {
    const labels = $(elements)
      .map(function () {
        return $(this).text().trim();
      })
      .get();
    const values = labels.elementWitoutDuplicates();
    return (() => {
      const result = [];
      for (var element of elements) {
        var text = $(element).text().trim();
        if (values.includes(text)) {
          result.push(this.removeDuplicateWarning(element));
        } else {
          result.push(undefined);
        }
      }
      return result;
    })();
  }

  removeFieldDuplicate() {
    if ($('#trackings').is(':visible') && $('.nested-fields').is(':visible')) {
      const elementFrmbs = $('ul.frmb:visible');
      return (() => {
        const result = [];
        for (var element of elementFrmbs) {
          var elements = $(element).find('.field-label:visible');
          result.push(this.getNoneDuplicateLabel(elements));
        }
        return result;
      })();
    } else {
      const elements = $('ul.frmb:visible .field-label:visible');
      return this.getNoneDuplicateLabel(elements);
    }
  }

  removeDuplicateWarning(element) {
    const field = $(element).parents('li.form-field');
    $(field).removeClass('has-error');
    $(field).find('input, textarea, select').removeClass('error');
    $(field).find('label.error').remove();
    if ($('#custom-field-submit').length) {
      return $('#custom-field-submit').removeAttr('disabled');
    }
  }
};
