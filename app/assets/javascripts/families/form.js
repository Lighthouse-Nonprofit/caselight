CIF.FamiliesNew =
  CIF.FamiliesCreate =
  CIF.FamiliesEdit =
  CIF.FamiliesUpdate =
    (function () {
      const _init = () => _initSelect2();

      var _initSelect2 = () => $('select').select2({ allowClear: true }, _clearSelectedOption());

      var _clearSelectedOption = function () {
        const formAction = $('body').attr('id');
        if (!formAction.includes('edit')) {
          return $('#family_family_type').val('');
        }
      };

      return { init: _init };
    })();
