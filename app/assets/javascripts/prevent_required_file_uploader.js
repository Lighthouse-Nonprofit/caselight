CIF.PreventRequiredFileUploader = class PreventRequiredFileUploader {
  preventFileUploader() {
    const form = $('form.simple_form');
    return $(form).on('submit', function (e) {
      const requiredFields = $('input[type="file"]').parents('div.required');
      return (() => {
        const result = [];
        for (var requiredField of requiredFields) {
          if ($(requiredField).parent().data('used')) {
            continue;
          }
          if ($(requiredField).find('input').val() === '') {
            $(requiredField).parent().addClass('has-error');
            $(requiredField).siblings('.form-text').removeClass('hidden');
            result.push(e.preventDefault());
          } else {
            $(requiredField).parent().removeClass('has-error');
            result.push($(requiredField).siblings('.form-text').addClass('hidden'));
          }
        }
        return result;
      })();
    });
  }
};
