CIF.Data_trackersIndex = (function () {
  const _init = function () {
    _submitPerPageParams();
    _initProgramRule();
    _initSelect2();
    return _handleDisabledInputs();
  };

  var _submitPerPageParams = () =>
    $('#per_page_form form select').on('change', () => $('#per_page_form form').submit());

  var _initProgramRule = function () {
    if ($('#after, #before').length <= 0) {
      return false;
    }
    return $.ajax({
      url: '/api/program_stream_add_rule/get_fields',
      method: 'GET',
      success(response) {
        // bare-array API response (the old response.program_stream_add_rule read was
        // undefined — POAM-017f latent defect); two independent read-only instances,
        // one per version-diff side. readOnly renders no buttons + disables inputs,
        // replacing the old render-then-strip hacks.
        const fieldList = response;
        new CIF.RuleBuilder($('#program-rules-before')[0], { filters: fieldList, readOnly: true });
        new CIF.RuleBuilder($('#program-rules-after')[0], { filters: fieldList, readOnly: true });
        setTimeout(() => _handleDisabledInputs());

        return _handleSetRules();
      },
    });
  };

  var _initSelect2 = () => CIF.Select.init('select');

  var _handleSetRules = function () {
    let rules = $('#rule-before').data('program-rules');
    if (!$.isEmptyObject(rules)) {
      CIF.RuleBuilder.get($('#program-rules-before')[0]).setRules(rules);
    }

    rules = $('#rule-after').data('program-rules');
    if (!$.isEmptyObject(rules)) {
      return CIF.RuleBuilder.get($('#program-rules-after')[0]).setRules(rules);
    }
  };

  // NB cosmetic delta vs QueryBuilder: this surface's old option object omitted the
  // is_not_empty label override, so historic rules using it now render "is not blank"
  // instead of QB's default "is not empty" — deliberate, module-default labels apply.

  var _handleDisabledInputs = () =>
    $('.modal-body .rules-group-container')
      .find('input, select, textarea, .group-conditions label')
      .attr('disabled', 'disabled');

  return { init: _init };
})();
