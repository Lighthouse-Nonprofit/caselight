CIF.PartnersNew =
  CIF.PartnersCreate =
  CIF.PartnersEdit =
  CIF.PartnersUpdate =
    (function () {
      const _init = () => _initSelect2();

      var _initSelect2 = () =>
        $('select').select2({
          allowClear: true,
        });

      return { init: _init };
    })();
