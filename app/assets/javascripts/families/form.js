CIF.FamiliesNew =
  CIF.FamiliesCreate =
  CIF.FamiliesEdit =
  CIF.FamiliesUpdate =
    (function () {
      const _init = () => _initSelect2();

      var _initSelect2 = function () {
        // pre-Tom-Select this ran as an (ignored) 2nd argument to .select2(), i.e. BEFORE init
        _clearSelectedOption();
        return CIF.Select.init('select', { allowClear: true });
      };

      var _clearSelectedOption = function () {
        const formAction = $('body').attr('id');
        if (!formAction.includes('edit')) {
          return $('#family_family_type').val('');
        }
      };

      return { init: _init };
    })();
