CIF.Client_advanced_searchesIndex = (function () {
  const optionTranslation = $('#opt-group-translation');
  const BASIC_FIELD_TRANSLATE = $(optionTranslation).data('basicFields');
  const CUSTOM_FORM_TRANSLATE = $(optionTranslation).data('customForm');
  const ENROLLMENT_TRANSLATE = $(optionTranslation).data('enrollment');
  const EXIT_PROGRAM_TRANSTATE = $(optionTranslation).data('exitProgram');
  const QUANTITATIVE_TRANSLATE = $(optionTranslation).data('quantitative');
  const TRACKING_TRANSTATE = $(optionTranslation).data('tracking');

  const ENROLLMENT_URL = '/api/client_advanced_searches/get_enrollment_field';
  const TRACKING_URL = '/api/client_advanced_searches/get_tracking_field';
  const EXIT_PROGRAM_URL = '/api/client_advanced_searches/get_exit_program_field';
  const CUSTOM_FORM_URL = '/api/client_advanced_searches/get_custom_field';

  this.enrollmentCheckbox = $('#enrollment-checkbox');
  this.trackingCheckbox = $('#tracking-checkbox');
  this.exitCheckbox = $('#exit-form-checkbox');
  this.customFormSelected = [];
  this.programSelected = [];

  const _init = function () {
    this.filterTranslation = '';
    _initSelect2();
    _setValueToBuilderSelected();
    _getTranslation();
    _initBuilderFilter();

    _handleShowCustomFormSelect();
    _customFormSelectChange();
    _customFormSelectRemove();
    _handleHideCustomFormSelect();

    _handleShowProgramStreamFilter();
    _handleHideProgramStreamSelect();
    _handleProgramSelectChange();
    _triggerEnrollmentFields();
    _triggerTrackingFields();
    _triggerExitProgramFields();
    _handleSelect2RemoveProgram();
    _handleUncheckedEnrollment();
    _handleUncheckedTracking();
    _handleUncheckedExitProgram();

    _handleAddQuantitativeFilter();
    _handleRemoveQuantitativFilter();

    _columnsVisibility();
    _handleInitDatatable();
    _handleSearch();
    _addRuleCallback();
    _filterSelectChange();
    _handleScrollTable();
    _getClientPath();
    return _setDefaultCheckColumnVisibilityAll();
  };

  var _initSelect2 = function () {
    $('#custom-form-select, #program-stream-select, #quantitative-case-select').select2();
    $('.rule-filter-container select').select2({ width: '250px' });
    return $('.rule-operator-container select, .rule-value-container select').select2({
      width: 'resolve',
    });
  };

  var _setValueToBuilderSelected = function () {
    this.customFormSelected = $('.custom-form').data('value');
    return (this.programSelected = $('.program-stream').data('value'));
  };

  var _handleAddQuantitativeFilter = function () {
    const fields = $('#quantitative-fields').data('fields');
    return $('#quantitative-type-checkbox').on('ifChecked', function () {
      $('#builder').queryBuilder('addFilter', fields);
      return _initSelect2();
    });
  };

  var _handleRemoveQuantitativFilter = () =>
    $('#quantitative-type-checkbox').on('ifUnchecked', () =>
      _handleRemoveFilterBuilder(QUANTITATIVE_TRANSLATE, QUANTITATIVE_TRANSLATE),
    );

  var _handleShowProgramStreamFilter = function () {
    if ($('#program-stream-checkbox').prop('checked')) {
      $('.program-stream').show();
    }
    if (
      this.enrollmentCheckbox.prop('checked') ||
      this.trackingCheckbox.prop('checked') ||
      this.exitCheckbox.prop('checked') ||
      this.programSelected.length > 0
    ) {
      $('.program-association').show();
    }
    return $('#program-stream-checkbox').on('ifChecked', () => $('.program-stream').show());
  };

  var _handleHideProgramStreamSelect = function () {
    const self = this;
    return $('#program-stream-checkbox').on('ifUnchecked', function () {
      $('#program-stream-column ul.append-child li').remove();
      self.programSelected = [];
      $('.program-stream, .program-association').hide();
      $('#program-stream-select option:selected').each(function () {
        const name = $(this).text();
        _handleRemoveFilterBuilder(name, BASIC_FIELD_TRANSLATE);
        _handleRemoveFilterBuilder(name, TRACKING_TRANSTATE);
        return _handleRemoveFilterBuilder(name, EXIT_PROGRAM_TRANSTATE);
      });
      $('.program-association input[type="checkbox"]').iCheck('uncheck');
      return $('#program-stream-select').select2('val', '');
    });
  };

  var _triggerEnrollmentFields = function () {
    const self = this;
    return $('#enrollment-checkbox').on('ifChecked', () =>
      _addCustomBuildersFields(self.programSelected, ENROLLMENT_URL),
    );
  };

  var _triggerTrackingFields = function () {
    const self = this;
    return $('#tracking-checkbox').on('ifChecked', () =>
      _addCustomBuildersFields(self.programSelected, TRACKING_URL),
    );
  };

  var _triggerExitProgramFields = function () {
    const self = this;
    return $('#exit-form-checkbox').on('ifChecked', () =>
      _addCustomBuildersFields(self.programSelected, EXIT_PROGRAM_URL),
    );
  };

  var _handleUncheckedEnrollment = () =>
    $('#enrollment-checkbox').on('ifUnchecked', () =>
      (() => {
        const result = [];
        for (var option of $('#program-stream-select option:selected')) {
          var name = $(option).text();
          var programName = name.trim();
          var headerClass = _formatSpecialCharacter(`${programName} Enrollment`);

          _removeCheckboxColumnPicker('#program-stream-column', headerClass);
          result.push(_handleRemoveFilterBuilder(name, ENROLLMENT_TRANSLATE));
        }
        return result;
      })(),
    );

  var _handleUncheckedTracking = () =>
    $('#tracking-checkbox').on('ifUnchecked', () =>
      (() => {
        const result = [];
        for (var option of $('#program-stream-select option:selected')) {
          var name = $(option).text();
          var programName = name.trim();
          var headerClass = _formatSpecialCharacter(`${programName} Tracking`);

          _removeCheckboxColumnPicker('#program-stream-column', headerClass);
          result.push(_handleRemoveFilterBuilder(name, TRACKING_TRANSTATE));
        }
        return result;
      })(),
    );

  var _handleUncheckedExitProgram = () =>
    $('#exit-form-checkbox').on('ifUnchecked', () =>
      (() => {
        const result = [];
        for (var option of $('#program-stream-select option:selected')) {
          var name = $(option).text();
          var programName = name.trim();
          var headerClass = _formatSpecialCharacter(`${programName} Exit Program`);

          _removeCheckboxColumnPicker('#program-stream-column', headerClass);
          result.push(_handleRemoveFilterBuilder(name, EXIT_PROGRAM_TRANSTATE));
        }
        return result;
      })(),
    );

  var _handleSelect2RemoveProgram = function () {
    const self = this;
    return $('#program-stream-select').on('select2-removed', function (element) {
      const programName = element.choice.text;
      const programStreamKeyword = ['Enrollment', 'Tracking', 'Exit Program'];
      _.forEach(programStreamKeyword, function (value) {
        const headerClass = _formatSpecialCharacter(`${programName.trim()} ${value}`);
        return _removeCheckboxColumnPicker('#program-stream-column', headerClass);
      });

      $.map(self.programSelected, function (val, i) {
        if (parseInt(val) === parseInt(element.val)) {
          return self.programSelected.splice(i, 1);
        }
      });

      _handleRemoveFilterBuilder(programName, ENROLLMENT_TRANSLATE);
      setTimeout(function () {
        _handleRemoveFilterBuilder(programName, TRACKING_TRANSTATE);
        return _handleRemoveFilterBuilder(programName, EXIT_PROGRAM_TRANSTATE);
      });
      if ($.isEmptyObject($(this).val())) {
        const programStreamAssociation = $('.program-association');
        $(programStreamAssociation).find('.i-checks').iCheck('uncheck');
        return $(programStreamAssociation).hide();
      }
    });
  };

  var _handleProgramSelectChange = function () {
    const self = this;
    return $('#program-stream-select').on('select2-selecting', function (psElement) {
      const programId = psElement.val;
      self.programSelected.push(programId);
      $('.program-association').show();
      if ($('#enrollment-checkbox').prop('checked')) {
        _addCustomBuildersFields(programId, ENROLLMENT_URL);
      }
      if ($('#tracking-checkbox').prop('checked')) {
        _addCustomBuildersFields(programId, TRACKING_URL);
      }
      if ($('#exit-form-checkbox').prop('checked')) {
        return _addCustomBuildersFields(programId, EXIT_PROGRAM_URL);
      }
    });
  };

  var _handleShowCustomFormSelect = function () {
    if ($('#custom-form-checkbox').prop('checked')) {
      $('.custom-form').show();
    }
    return $('#custom-form-checkbox').on('ifChecked', () => $('.custom-form').show());
  };

  var _handleHideCustomFormSelect = function () {
    const self = this;
    return $('#custom-form-checkbox').on('ifUnchecked', function () {
      $('#custom-form-column ul.append-child li').remove();

      $('#custom-form-select option:selected').each(function () {
        const formTitle = $(this).text();
        return _handleRemoveFilterBuilder(formTitle, CUSTOM_FORM_TRANSLATE);
      });

      self.customFormSelected = [];
      $('.custom-form select').select2('val', '');
      return $('.custom-form').hide();
    });
  };

  var _customFormSelectChange = function () {
    const self = this;
    return $('#custom-form-wrapper select').on('select2-selecting', function (element) {
      self.customFormSelected.push(element.val);
      return _addCustomBuildersFields(element.val, CUSTOM_FORM_URL);
    });
  };

  var _customFormSelectRemove = function () {
    const self = this;
    return $('#custom-form-wrapper select').on('select2-removed', function (element) {
      const removeValue = element.choice.text;
      let formTitle = removeValue.trim();
      formTitle = _formatSpecialCharacter(`${formTitle} Custom Form`);

      _removeCheckboxColumnPicker('#custom-form-column', formTitle);
      $.map(self.customFormSelected, function (val, i) {
        if (parseInt(val) === parseInt(element.val)) {
          return self.customFormSelected.splice(i, 1);
        }
      });

      return setTimeout(() => _handleRemoveFilterBuilder(removeValue, CUSTOM_FORM_TRANSLATE), 100);
    });
  };

  const _addFieldToColumnPicker = function (element, fieldList) {
    const customFormColumnPicker = $(`${element} ul.append-child`);
    const fieldsGroupByOptgroup = _.groupBy(fieldList, 'optgroup');

    return _.forEach(fieldsGroupByOptgroup, function (values, key) {
      const headerClass = _formBuiderFormatHeader(key);
      $(customFormColumnPicker).append(`<li class='dropdown-header ${headerClass}'>${key}</li>`);
      return _.forEach(values, function (value) {
        const fieldName = value.id;
        const keyword = _.first(fieldName.split('_'));
        if (keyword !== 'enrollmentdate' && keyword !== 'programexitdate') {
          const checkField = _formatSpecialCharacter(fieldName);
          const { label } = value;
          $(customFormColumnPicker).append(_checkboxElement(checkField, headerClass, label));
          return $(`.${headerClass} input.i-checks`).iCheck({
            checkboxClass: 'icheckbox_square-green',
          });
        }
      });
    });
  };

  var _formBuiderFormatHeader = function (value) {
    const keyWords = value.split('|');
    const name = _.first(keyWords).trim();
    const label = _.last(keyWords).trim();
    const combine = `${name} ${label}`;
    return _formatSpecialCharacter(combine);
  };

  var _formatSpecialCharacter = function (value) {
    const filedName = value
      .toLowerCase()
      .replace(/[^a-zA-Z0-9]+/gi, ' ')
      .trim();
    return filedName.replace(/ /g, '_');
  };

  var _removeCheckboxColumnPicker = (element, name) =>
    $(`${element} ul.append-child li.${name}`).remove();

  var _checkboxElement = (field, name, label) => `<li class='visibility checkbox-margin ${name}'> \
<input type='checkbox' name='${field}_' id='${field}_' value='${field}' class='i-checks' style='position: absolute; opacity: 0;'> \
<label for='${field}_'>${label}</label> \
</li>`;

  var _addCustomBuildersFields = function (ids, url) {
    const action = _.last(url.split('/'));
    const element =
      action === 'get_custom_field' ? '#custom-form-column' : '#program-stream-column';
    return $.ajax({
      url,
      data: { ids },
      method: 'GET',
      success(response) {
        const fieldList = response.client_advanced_searches;
        $('#builder').queryBuilder('addFilter', fieldList);
        _initSelect2();
        return _addFieldToColumnPicker(element, fieldList);
      },
    });
  };

  var _initBuilderFilter = function () {
    const builderFields = $('#client-builder-fields').data('fields');
    $('#builder').queryBuilder(_queryBuilderOption(builderFields));
    _basicFilterSetRule();
    _initSelect2();
    return _initRuleOperatorSelect2($('#builder'));
  };

  var _handleSearch = function () {
    const self = this;
    return $('#search').on('click', function () {
      const basicRules = $('#builder').queryBuilder('getRules');
      const customFormValues =
        self.customFormSelected.length > 0 ? `[${self.customFormSelected}]` : undefined;
      const programValues =
        self.programSelected.length > 0 ? `[${self.programSelected}]` : undefined;

      _setValueToProgramAssociation();
      $('#client_advanced_search_custom_form_selected').val(customFormValues);
      $('#client_advanced_search_program_selected').val(programValues);
      if ($('#quantitative-type-checkbox').prop('checked')) {
        $('#client_advanced_search_quantitative_check').val(1);
      }

      if (!$.isEmptyObject(basicRules)) {
        $('#client_advanced_search_basic_rules').val(_handleStringfyRules(basicRules));
        _handleSelectFieldVisibilityCheckBox();
        return $('#advanced-search').submit();
      }
    });
  };

  var _setValueToProgramAssociation = function () {
    const enrollmentCheck = $('#client_advanced_search_enrollment_check');
    const trackingCheck = $('#client_advanced_search_tracking_check');
    const exitFormCheck = $('#client_advanced_search_exit_form_check');

    if (this.enrollmentCheckbox.prop('checked')) {
      $(enrollmentCheck).val(1);
    }
    if (this.trackingCheckbox.prop('checked')) {
      $(trackingCheck).val(1);
    }
    if (this.exitCheckbox.prop('checked')) {
      return $(exitFormCheck).val(1);
    }
  };

  var _queryBuilderOption = function (fieldList) {
    return {
      inputs_separator: ' AND ',
      icons: {
        remove_rule: 'fa fa-minus',
      },
      lang: {
        delete_rule: '',
        add_rule: this.filterTranslation.addFilter,
        add_group: this.filterTranslation.addGroup,
        delete_group: this.filterTranslation.deleteGroup,
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
      plugins: ['sortable', 'bt-tooltip-errors'],
      filters: fieldList,
    };
  };

  var _columnsVisibility = function () {
    $('.columns-visibility').click((e) => e.stopPropagation());

    const allCheckboxes = $('#client-column .all-visibility #all_');

    allCheckboxes.on('ifChecked', () =>
      $('#client-column .visibility input[type=checkbox]').iCheck('check'),
    );
    return allCheckboxes.on('ifUnchecked', () =>
      $('#client-column .visibility input[type=checkbox]').iCheck('uncheck'),
    );
  };

  var _setDefaultCheckColumnVisibilityAll = () =>
    setTimeout(function () {
      const clientCheckboxChecked = $('#client-column .visibility .checked');
      const programCheckboxChecked = $('#program-stream-column .visibility .checked');
      const customFormCheckboxChecked = $('#custom-form-column .visibility .checked');
      if (
        $(clientCheckboxChecked).length === 0 &&
        $(programCheckboxChecked).length === 0 &&
        $(customFormCheckboxChecked).length === 0
      ) {
        return $('#client-column .all-visibility #all_').iCheck('check');
      }
    });

  var _addRuleCallback = () =>
    $('#builder').on('afterCreateRuleFilters.queryBuilder', function (_e, obj) {
      _initSelect2();
      _handleSelectOptionChange(obj);
      return _referred_to_program();
    });

  var _handleSelectOptionChange = function (obj) {
    if (obj !== undefined) {
      const rowBuilderRule = obj.$el[0];
      const ruleFiltersSelect = $(rowBuilderRule).find('.rule-filter-container select');
      return $(ruleFiltersSelect).on('select2-close', () =>
        setTimeout(function () {
          _initSelect2();
          return _initRuleOperatorSelect2(rowBuilderRule);
        }),
      );
    }
  };

  var _filterSelectChange = () =>
    $('.rule-filter-container select').on('select2-close', () => setTimeout(() => _initSelect2()));

  var _initRuleOperatorSelect2 = function (rowBuilderRule) {
    const operatorSelect = $(rowBuilderRule).find('.rule-operator-container select');
    return $(operatorSelect).on('select2-close', () =>
      setTimeout(() =>
        $(rowBuilderRule).find('.rule-value-container select').select2({ width: '180px' }),
      ),
    );
  };

  var _handleRemoveFilterBuilder = function (resourceName, resourcelabel) {
    let filterSelects = $('.rule-container .rule-filter-container select');
    for (var select of filterSelects) {
      var optGroup = $(':selected', select).parents('optgroup');
      if (
        $(select).val() !== '-1' &&
        optGroup[0] !== undefined &&
        optGroup[0].label !== BASIC_FIELD_TRANSLATE
      ) {
        var label = optGroup[0].label.split('|');
        if ($(label).last()[0].trim() === resourcelabel && label[0].trim() === resourceName) {
          var container = $(select).parents('.rule-container');
          $(container).find('select').select2('destroy');
          $(container).find('.rule-header button').trigger('click');
        }
      }
    }

    return setTimeout(function () {
      if ($('.rule-container .rule-filter-container select').length === 0) {
        $('button[data-add="rule"]').trigger('click');
        filterSelects = $('.rule-container .rule-filter-container select');
      }
      return _handleRemoveBuilderOption(filterSelects, resourceName, resourcelabel);
    });
  };

  var _handleRemoveBuilderOption = function (filterSelects, resourceName, resourcelabel) {
    const values = [];
    const optGroups = $(filterSelects[0]).find('optgroup');
    for (var optGroup of optGroups) {
      var { label } = optGroup;
      if (label !== BASIC_FIELD_TRANSLATE) {
        var labelValue = label.split('|');
        if (
          $(labelValue).last()[0].trim() === resourcelabel &&
          labelValue[0].trim() === resourceName
        ) {
          $(optGroup)
            .find('option')
            .each(function () {
              return values.push($(this).val());
            });
        }
      }
    }
    $('#builder').queryBuilder('removeFilter', values);
    return _initSelect2();
  };

  var _referred_to_program = () =>
    $('.rule-filter-container select').change(function () {
      const selectedOption = $(this).find('option:selected');
      const selectedOptionValue = $(selectedOption).val();
      if (
        selectedOptionValue === 'referred_to_ec' ||
        selectedOptionValue === 'referred_to_fc' ||
        selectedOptionValue === 'referred_to_kc'
      ) {
        return setTimeout(
          () =>
            $(selectedOption)
              .parents('.rule-filter-container')
              .siblings('.rule-operator-container')
              .find('select option[value="is_empty"]')
              .remove(),
          10,
        );
      }
    });

  var _getTranslation = function () {
    return (this.filterTranslation = {
      addFilter: $('#builder').data('filter-translation-add-filter'),
      addGroup: $('#builder').data('filter-translation-add-group'),
      deleteGroup: $('#builder').data('filter-translation-delete-group'),
    });
  };

  var _basicFilterSetRule = function () {
    const basicQueryRules = $('#builder').data('basic-search-rules');
    if (!$.isEmptyObject(basicQueryRules)) {
      return $('#builder').queryBuilder('setRules', basicQueryRules);
    }
  };

  var _handleInitDatatable = () =>
    $('.clients-table table').DataTable({
      sScrollY: 'auto',
      bFilter: false,
      bAutoWidth: true,
      bSort: false,
      sScrollX: '100%',
      bInfo: false,
      bLengthChange: false,
      bPaginate: false,
    });

  var _handleStringfyRules = function (rules) {
    rules = JSON.stringify(rules);
    return rules.replace(/null/g, '""');
  };

  var _handleSelectFieldVisibilityCheckBox = function () {
    const checkedFields = $('.visibility .checked input, .all-visibility .checked input');
    return $('form#advanced-search').append(checkedFields);
  };

  var _handleScrollTable = () =>
    $(window).load(function () {
      const ua = navigator.userAgent;
      if (
        !/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile|mobile|CriOS/i.test(
          ua,
        )
      ) {
        return $('.clients-table .dataTables_scrollBody').niceScroll({
          scrollspeed: 30,
          cursorwidth: 10,
          cursoropacitymax: 0.4,
        });
      }
    });

  var _getClientPath = () =>
    $('table.clients tbody tr').click(function (e) {
      if ($(e.target).hasClass('btn') || $(e.target).hasClass('fa')) {
        return;
      }
      return (window.location = $(this).data('href'));
    });

  return { init: _init };
})();
