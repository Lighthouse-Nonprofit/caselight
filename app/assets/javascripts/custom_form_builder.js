CIF.CustomFormBuilder = class CustomFormBuilder {
  constructor() {}

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
    return $('.field-actions a.icon-pencil').click(() =>
      $(".form-elements input[name='label']").on('change', () =>
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
