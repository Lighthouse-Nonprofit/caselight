CIF.ClientsIndex = (function () {
  const _init = function () {
    _enableSelect2();
    _columnsVisibility();
    _fixedHeaderTableColumns();
    _cssClassForlabelDynamic();
    _restrictNumberFilter();
    _quantitativeCaesByQuantitativeType();
    _clickMenuResizeChart();
    _handleHideShowReport();
    _formatReportxAxis();
    _handleCreateCaseReport();
    _handleCreateCsiDomainReport();
    _handleScrollTable();
    _setDefaultCheckColumnVisibilityAll();
    return _getClientPath();
  };

  var _setDefaultCheckColumnVisibilityAll = function () {
    if ($('.visibility .checked').length === 0) {
      return $('.all-visibility #all_').iCheck('check');
    }
  };

  const _infiniteScroll = () =>
    $('table.clients .page').infinitescroll({
      navSelector: 'ul.pagination', // selector for the paged navigation (it will be hidden)
      nextSelector: 'ul.pagination a[rel=next]', // selector for the NEXT link (to page 2)
      itemSelector: 'table.clients tbody tr', // selector for all items you'll retrieve
      loading: {
        img: 'http://i.imgur.com/qkKy8.gif',
        msgText: $('.clients-table').data('info-load'),
      },
      donetext: $('.clients-table').data('info-end'),
      binder: $('.clients-table .dataTables_scrollBody'),
    });

  var _handleCreateCsiDomainReport = function () {
    const element = $('#cis-domain-score');
    const csiData = element.data('csi-domain');
    const csiTitle = element.data('title');
    const csiyAxisTitle = element.data('yaxis-title');

    const report = new CIF.ReportCreator(csiData, csiTitle, csiyAxisTitle, element);
    return report.lineChart();
  };

  var _handleCreateCaseReport = function () {
    const element = $('#case-statistic');
    const caseData = element.data('case-statistic');
    const caseTitle = element.data('title');
    const caseyAxisTitle = element.data('yaxis-title');

    const report = new CIF.ReportCreator(caseData, caseTitle, caseyAxisTitle, element);
    return report.lineChart();
  };

  var _enableSelect2 = () => CIF.Select.init('#clients-index select', { allowClear: true });

  var _formatReportxAxis = function () {
    // UNIT 11: was a global useUTC:false call on the former charting library. Chart.js has no
    // such global and the line-chart x-axis is CATEGORICAL (pre-formatted string labels, never
    // date-parsed), so no timezone normalization is needed. Kept as a no-op so the _init() call
    // list and this module's shape stay unchanged.
  };

  var _handleHideShowReport = () =>
    $('#client-statistic').click(function () {
      $('#client-statistic-body').slideToggle('slow');
      return _handleResizeWindow();
    });

  var _clickMenuResizeChart = () =>
    $('.minimalize-styl-2').click(() => setTimeout(() => _handleResizeWindow(), 220));

  var _handleResizeWindow = () => window.dispatchEvent(new Event('resize'));

  var _columnsVisibility = function () {
    $('.columns-visibility').click((e) => e.stopPropagation());

    const allCheckboxes = $('.all-visibility #all_');

    allCheckboxes.on('ifChecked', () => $('.visibility input[type=checkbox]').iCheck('check'));
    return allCheckboxes.on('ifUnchecked', () =>
      $('.visibility input[type=checkbox]').iCheck('uncheck'),
    );
  };

  var _fixedHeaderTableColumns = function () {
    const sInfoShow = $('#sinfo').data('infoshow');
    const sInfoTo = $('#sinfo').data('infoto');
    const sInfoTotal = $('#sinfo').data('infototal');
    $('.clients-table').removeClass('table-responsive');
    if (!$('table.clients tbody tr td').hasClass('noresults')) {
      return $('table.clients').dataTable({
        sScrollY: 'auto',
        bFilter: false,
        bAutoWidth: true,
        bSort: false,
        sScrollX: '100%',
        bInfo: false,
        bLengthChange: false,
        bPaginate: false,
      });
    } else {
      return $('.clients-table').addClass('table-responsive');
    }
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

  var _handleScrollTable = () =>
    $(window).on('load', function () {
      const ua = navigator.userAgent;
      if (
        !/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile|mobile|CriOS/i.test(
          ua,
        )
      ) {
        $('.clients-table .dataTables_scrollBody').niceScroll({
          scrollspeed: 30,
          cursorwidth: 10,
          cursoropacitymax: 0.4,
        });
        return _handleResizeWindow();
      }
    });

  var _getClientPath = function () {
    if (
      $('table.clients tbody tr').text().trim() === 'No results found' ||
      $('table.clients tbody tr').text().trim() === 'មិនមានលទ្ធផល' ||
      $('table.clients tbody tr').text().trim() === 'No data available in table'
    ) {
      return;
    }
    $('table.clients tbody tr').click(function (e) {
      if ($(e.target).hasClass('btn') || $(e.target).hasClass('fa')) {
        return;
      }
      return (window.location = $(this).data('href'));
    });

    if (
      $('table.clients tbody tr').text().trim() === 'No data available in table' ||
      $('table.clients tbody tr').text().trim() === 'មិនមានលទ្ធផល'
    ) {
      return;
    }
  };

  return { init: _init };
})();
