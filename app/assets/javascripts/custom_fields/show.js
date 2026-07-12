CIF.Custom_fieldsShow = CIF.Custom_fieldsPreview = (function () {
  const _init = () => _initFormBuilder();

  var _initFormBuilder = function () {
    const builderOption = new CIF.CustomFormBuilder();
    const fields = `${$('.build-wrap').data('fields')}` || '';
    // formBuilder 3.x returns the instance directly; shared options from builderOptions
    return $('.build-wrap').formBuilder(
      builderOption.builderOptions({ formData: fields.replace(/=>/g, ':'), sticky: true }),
    );
  };

  return { init: _init };
})();
