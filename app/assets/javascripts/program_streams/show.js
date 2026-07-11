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
        const fieldList = response.program_stream_add_rule;
        $('#program-rules').queryBuilder(_queryBuilderOption(fieldList));
        setTimeout(function () {
          _initSelect2();
          _handleRemoveButtonOnProgramRules();
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
      theme: 'explorer',
    });

  var _initSelect2 = function () {
    $('.rule-filter-container select').select2({ width: '220px' });
    return $('.rule-operator-container select, .rule-value-container select').select2({
      width: '180px',
    });
  };

  var _handleSetRules = function () {
    const rules = $('#rules').data('program-rules');
    if (!$.isEmptyObject(rules)) {
      return $('#program-rules').queryBuilder('setRules', rules);
    }
  };

  var _queryBuilderOption = (fieldList) => ({
    inputs_separator: ' AND ',

    lang: {
      operators: {
        is_empty: 'is blank',
        is_not_empty: 'is not blank',
        equal: 'is',
        not_equal: 'is not',
        less: '<',
        less_or_equal: '<=',
        greater: '>',
        greater_or_equal: '>=',
        contains: 'includes',
        not_contains: 'excludes',
      },
    },

    filters: fieldList,
  });

  var _handleRemoveButtonOnProgramRules = () => $('.panel').find('#program-rules button').remove();

  var _handleDisabledInputs = function () {
    $('#program-stream-info :input').attr('disabled', 'disabled');
    return $('#program-stream-info .rules-group-header .group-conditions label').attr(
      'disabled',
      'disabled',
    );
  };

  return { init: _init };
})();
