CIF.Client_custom_fieldsNew =
  CIF.Client_custom_fieldsCreate =
  CIF.Client_custom_fieldsEdit =
  CIF.Client_custom_fieldsUpdate =
    (function () {
      const _init = () => _select2();

      var _select2 = () =>
        $('select').select2({
          minimumInputLength: 0,
        });

      return { init: _init };
    })();
