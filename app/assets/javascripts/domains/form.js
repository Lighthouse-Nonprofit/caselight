CIF.DomainsNew =
  CIF.DomainsCreate =
  CIF.DomainsEdit =
  CIF.DomainsUpdate =
    (function () {
      // POAM-017a: TinyMCE init removed — the Trix editor (<trix-editor> in the form
      // partial) binds itself; app-wide Trix config lives in rich_text.js.
      const _init = () => _initSelect2();

      var _initSelect2 = () => CIF.Select.init('.select2');
      return { init: _init };
    })();
