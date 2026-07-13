CIF.Program_streamsShow = CIF.Program_streamsPreview = (function () {
  const _init = function () {
    _initFileInput();
    _initProgramRule();
    _handleDisabledInputs();
    return _initSelect2();
  };

  var _initProgramRule = function () {
    const rules = $('#rules').data('program-rules');
    if ($.isEmptyObject(rules)) {
      return;
    }
    return $.ajax({
      url: '/api/program_stream_add_rule/get_fields',
      method: 'GET',
      success(response) {
        // bare-array API response (the old response.program_stream_add_rule read was
        // undefined — POAM-017f latent defect); readOnly renders no buttons and
        // disables every input, replacing the old render-then-strip hacks
        const fieldList = response;
        new CIF.RuleBuilder($('#program-rules')[0], { filters: fieldList, readOnly: true });
        setTimeout(function () {
          _initSelect2();
          return _handleDisabledInputs();
        });

        return _handleSetRules();
      },
    });
  };

  var _initFileInput = () =>
    $('.file').fileinput({
      showUpload: false,
      removeClass: 'btn btn-danger btn-outline',
      browseLabel: 'Browse',
      theme: 'explorer-fa4',
    });

  var _initSelect2 = function () {
    CIF.Select.init('.rule-filter-container select', { width: '220px' });
    return CIF.Select.init('.rule-operator-container select, .rule-value-container select', {
      width: '180px',
    });
  };

  var _handleSetRules = function () {
    const rules = $('#rules').data('program-rules');
    if (!$.isEmptyObject(rules)) {
      return CIF.RuleBuilder.get($('#program-rules')[0]).setRules(rules);
    }
  };

  var _handleDisabledInputs = function () {
    $('#program-stream-info :input').attr('disabled', 'disabled');
    return $('#program-stream-info .rules-group-header .group-conditions label').attr(
      'disabled',
      'disabled',
    );
  };

  return { init: _init };
})();
