CIF.UsersShow = (function () {
  const _init = function () {
    _fixedHeaderTableColumns();
    _handleScrollTable();
    return _getClientPath();
  };

  var _fixedHeaderTableColumns = function () {
    $('.clients-table').removeClass('table-responsive');
    if (!$('table.clients tbody tr td').hasClass('noresults')) {
      return $('table.clients').dataTable({
        bPaginate: false,
        bFilter: false,
        bInfo: false,
        bSort: false,
        sScrollY: 'auto',
        bAutoWidth: true,
        sScrollX: '100%',
      });
    } else {
      return $('.clients-table').addClass('table-responsive');
    }
  };

  var _handleScrollTable = () =>
    $(window).load(function () {
      const ua = navigator.userAgent;
      if (
        !/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|OperaMini|Mobile|mobile|CriOS/i.test(
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

  var _getClientPath = function () {
    if (
      $('table.clients tbody tr').text().trim() === 'No results found' ||
      $('table.clients tbody tr').text().trim() === 'មិនមានលទ្ធផល'
    ) {
      return;
    }
    return $('table.clients tbody tr').click(function (e) {
      if ($(e.target).hasClass('btn') || $(e.target).hasClass('fa')) {
        return;
      }
      return (window.location = $(this).data('href'));
    });
  };

  return { init: _init };
})();
