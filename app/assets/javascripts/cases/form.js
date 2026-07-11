CIF.CasesNew =
  CIF.CasesCreate =
  CIF.CasesUpdate =
  CIF.CasesEdit =
    (function () {
      const _init = () => _initSelect2();

      var _initSelect2 = () => $('select').select2();

      return { init: _init };
    })();
