CIF.CasesNew =
  CIF.CasesCreate =
  CIF.CasesUpdate =
  CIF.CasesEdit =
    (function () {
      const _init = () => _initSelect2();

      var _initSelect2 = () => CIF.Select.init('select');

      return { init: _init };
    })();
