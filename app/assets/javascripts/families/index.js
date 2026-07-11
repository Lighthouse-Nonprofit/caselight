CIF.FamiliesIndex = (function () {
  const _init = function () {
    _fixedHeaderTableColumns();
    _handleScrollTable();
    _getFamilyPath();
    return _initSelect2();
  };

  var _initSelect2 = () => CIF.Select.init('select', { allowClear: true });

  var _fixedHeaderTableColumns = function () {
    $('.families-table').removeClass('table-responsive');
    if (!$('table.families tbody tr td').hasClass('noresults')) {
      return $('table.families').dataTable({
        sScrollX: '100%',
        bPaginate: false,
        bFilter: false,
        bInfo: false,
        bSort: false,
        sScrollY: 'auto',
        bAutoWidth: true,
      });
    } else {
      return $('.families-table').addClass('table-responsive');
    }
  };

  var _handleScrollTable = () =>
    $(window).on('load', function () {
      const ua = navigator.userAgent;
      if (
        !/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile|mobile|CriOS/i.test(
          ua,
        )
      ) {
        return $('.families-table .dataTables_scrollBody').niceScroll({
          scrollspeed: 30,
          cursorwidth: 10,
          cursoropacitymax: 0.4,
        });
      }
    });

  var _getFamilyPath = function () {
    if (
      $('table.families tbody tr').text().trim() === 'No results found' ||
      $('table.families tbody tr').text().trim() === 'មិនមានលទ្ធផល'
    ) {
      return;
    }
    return $('table.families tbody tr').click(function (e) {
      if (
        $(e.target).hasClass('btn') ||
        $(e.target).hasClass('fa') ||
        $(e.target).hasClass('case-history')
      ) {
        return;
      }
      return (window.location = $(this).data('href'));
    });
  };

  return { init: _init };
})();
