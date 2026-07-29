CIF.ClientsIndex = (function () {
  // D1 (grid modernization): this module lost its dead half. `_fixedHeaderTableColumns`
  // (jquery.dataTables cosmetic init), `_handleScrollTable` (niceScroll), `_infiniteScroll`
  // (never even called) and `_getClientPath` (row click-through) all targeted the legacy
  // `table.clients` markup — the clients index renders the in-house `.record-grid` (UX round 3)
  // which ships its own navigation, so none of that code had anything to run against.
  // Investor UX round (2026-07): the chart plumbing (_handleHideShowReport, the two chart
  // creators, the resize + x-axis shims) moved to reports/index.js — the charts live on
  // /reports now and the index's "Reports" header entry is a plain link.
  const _init = function () {
    _enableSelect2();
    _columnsVisibility();
    _cssClassForlabelDynamic();
    _restrictNumberFilter();
    _quantitativeCaesByQuantitativeType();
    return _setDefaultCheckColumnVisibilityAll();
  };

  // D1 fix: the old guard tested `.visibility .checked` — iCheck's WRAPPER class, which stopped
  // existing at the POAM-017g flip — so this re-checked "all" on EVERY load, visually flagging
  // every column even when the user had a specific selection. Test the real inputs instead.
  var _setDefaultCheckColumnVisibilityAll = function () {
    if ($('.visibility input[type=checkbox]:checked').length === 0) {
      return $('.all-visibility #all_').prop('checked', true).trigger('change');
    }
  };

  var _enableSelect2 = () => CIF.Select.init('#clients-index select', { allowClear: true });

  // D1: bound to the NATIVE change event directly. The old ifChecked/ifUnchecked binding only
  // kept working via caselight_shell.js's iCheck compat shim (verified live before this change:
  // the cascade DID work through the shim) — the direct binding removes the indirection.
  var _columnsVisibility = function () {
    $('.columns-visibility').click((e) => e.stopPropagation());

    return $('.all-visibility #all_').on('change', function () {
      $('.visibility input[type=checkbox]').prop('checked', this.checked).trigger('change');
    });
  };

  var _cssClassForlabelDynamic = function () {
    $('.dynamic_filter').prev('label').css('display', 'block');
    return $('.dynamic_filter').find('.select2-search').remove('div');
  };

  var _restrictNumberFilter = function () {
    const arr = [
      'all_domains',
      'domain_1a',
      'domain_1b',
      'domain_2a',
      'domain_2b',
      'domain_3a',
      'domain_3b',
      'domain_4a',
      'domain_4b',
      'domain_5a',
      'domain_5b',
      'domain_6a',
      'domain_6b',
    ];
    $(arr).each((k, v) =>
      $(`.${v}.value`).keydown(function (e) {
        const charCode = e.which ? e.which : e.keyCode;
        if (charCode !== 46 && charCode > 31 && (charCode < 48 || charCode > 57)) {
          return false;
        }
        return true;
      }),
    );

    return $('input.age.float_filter').keydown(function (e) {
      if (
        $.inArray(e.keyCode, [46, 8, 9, 27, 13, 110, 190]) !== -1 ||
        (e.keyCode === 65 && e.ctrlKey === true) ||
        (e.keyCode === 67 && e.ctrlKey === true) ||
        (e.keyCode === 88 && e.ctrlKey === true) ||
        (e.keyCode >= 35 && e.keyCode <= 41)
      ) {
        return;
      }
      if ((e.shiftKey || e.keyCode < 48 || e.keyCode > 57) && (e.keyCode < 96 || e.keyCode > 105)) {
        e.preventDefault();
      }
    });
  };

  var _quantitativeCaesByQuantitativeType = function () {
    const self = this;
    const quantitativeType = $('#client_grid_quantitative_types');
    const closeTag = $('.quantitative_data').find('abbr');
    const quantitativeData = $('#client_grid_quantitative_data');
    quantitativeType.on('change', function () {
      const qValue = quantitativeType.val();
      // was: blank select2 v3's displayed text (.select2-chosen) + hide its clear abbr;
      // Tom Select's display and clear button follow the (silent) value clear instead
      CIF.Select.setValue(quantitativeData, '');
      return _quantitativeCaes(qValue);
    });
    quantitativeData.on('change', () => closeTag.show());
    return closeTag.click(() => closeTag.hide());
  };

  var _quantitativeCaes = (qValue) =>
    $.ajax({
      url: '/quantitative_data?id=' + qValue,
      method: 'GET',
      success(response) {
        const { data } = response;
        const option = [];
        $('#client_grid_quantitative_data').html('');
        $('#client_grid_quantitative_data').append('<option value=""></option>');

        $(data).each((index, value) =>
          $('#client_grid_quantitative_data').append(
            '<option value="' + data[index].id + '">' + data[index].value + '</option>',
          ),
        );
        // Tom Select caches options — re-import after the native <option> rebuild above
        return CIF.Select.refresh('#client_grid_quantitative_data');
      },
      error(error) {},
    });

  return { init: _init };
})();
