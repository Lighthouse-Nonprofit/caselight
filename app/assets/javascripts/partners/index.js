CIF.PartnersIndex = (function () {
  const _init = function () {
    _fixedHeaderTableColumns();
    _handleScrollTable();
    _getPartnerPath();
    return _initSelect2();
  };

  var _initSelect2 = () => CIF.Select.init('select', { allowClear: true });

  var _fixedHeaderTableColumns = function () {
    $('.partners-table').removeClass('table-responsive');
    if (!$('table.partners tbody tr td').hasClass('noresults')) {
      return $('table.partners').dataTable({
        bPaginate: false,
        bFilter: false,
        bInfo: false,
        bSort: false,
        sScrollY: 'auto',
        bAutoWidth: true,
        sScrollX: '100%',
      });
    } else {
      return $('.partners-table').addClass('table-responsive');
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
        return $('.partners-table .dataTables_scrollBody').niceScroll({
          scrollspeed: 30,
          cursorwidth: 10,
          cursoropacitymax: 0.4,
        });
      }
    });

  var _getPartnerPath = function () {
    if (
      $('table.partners tbody tr').text().trim() === 'No results found' ||
      $('table.partners tbody tr').text().trim() === 'មិនមានលទ្ធផល'
    ) {
      return;
    }
    return $('table.partners tbody tr').click(function (e) {
      if ($(e.target).hasClass('btn') || $(e.target).hasClass('fa')) {
        return;
      }
      return (window.location = $(this).data('href'));
    });
  };

  return { init: _init };
})();
