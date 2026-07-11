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
        const fieldList = response.program_stream_add_rule;
        $('#program-rules-before').queryBuilder(_queryBuilderOption(fieldList));
        $('#program-rules-after').queryBuilder(_queryBuilderOption(fieldList));
        setTimeout(function () {
          _handleRemoveButtonOnProgramRules();
          return _handleDisabledInputs();
        });

        return _handleSetRules();
      },
    });
  };

  var _initSelect2 = () => $('select').select2();

  var _handleSetRules = function () {
    let rules = $('#rule-before').data('program-rules');
    if (!$.isEmptyObject(rules)) {
      $('#program-rules-before').queryBuilder('setRules', rules);
    }

    rules = $('#rule-after').data('program-rules');
    if (!$.isEmptyObject(rules)) {
      return $('#program-rules-after').queryBuilder('setRules', rules);
    }
  };

  var _queryBuilderOption = (fieldList) => ({
    inputs_separator: ' AND ',

    lang: {
      operators: {
        is_empty: 'is blank',
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

  var _handleRemoveButtonOnProgramRules = function () {
    $('#program-rules-before').find('button').remove();
    return $('#program-rules-after').find('button').remove();
  };

  var _handleDisabledInputs = () =>
    $('.modal-body .rules-group-container')
      .find('input, select, textarea, .group-conditions label')
      .attr('disabled', 'disabled');

  return { init: _init };
})();
