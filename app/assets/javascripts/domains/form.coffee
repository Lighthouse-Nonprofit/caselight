CIF.DomainsNew = CIF.DomainsCreate = CIF.DomainsEdit = CIF.DomainsUpdate = do ->
  # POAM-017a: TinyMCE init removed — the Trix editor (<trix-editor> in the form
  # partial) binds itself; app-wide Trix config lives in rich_text.js.
  _init = ->
    _initSelect2()

  _initSelect2 = ->
    $('.select2').select2();
  { init: _init }
