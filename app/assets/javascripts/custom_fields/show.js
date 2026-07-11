CIF.Custom_fieldsShow = CIF.Custom_fieldsPreview = (function () {
  const _init = () => _initFormBuilder();

  var _initFormBuilder = function () {
    let formBuilder;
    const builderOption = new CIF.CustomFormBuilder();
    const fields = `${$('.build-wrap').data('fields')}` || '';
    return (formBuilder = $('.build-wrap')
      .formBuilder({
        dataType: 'json',
        formData: fields.replace(/=>/g, ':'),
        disableFields: ['autocomplete', 'header', 'hidden', 'paragraph', 'button', 'checkbox'],
        showActionButtons: false,
        messages: {
          cannotBeEmpty: 'name_separated_with_underscore',
        },
        stickyControls: {
          enable: true,
          offset: {
            top: 20,
            right: 20,
            left: 'auto',
          },
        },

        typeUserEvents: {
          'checkbox-group': builderOption.eventCheckboxOption(),
          date: builderOption.eventDateOption(),
          file: builderOption.eventFileOption(),
          number: builderOption.eventNumberOption(),
          'radio-group': builderOption.eventRadioOption(),
          select: builderOption.eventSelectOption(),
          text: builderOption.eventTextFieldOption(),
          textarea: builderOption.eventTextAreaOption(),
        },
      })
      .data('formBuilder'));
  };

  return { init: _init };
})();
