CIF.UsersIndex = (function () {
  const _init = function () {
    _fixedHeaderTableColumns();
    _handleScrollTable();
    return _getUserPath();
  };

  var _fixedHeaderTableColumns = function () {
    $('.users-table').removeClass('table-responsive');
    if (!$('table.users tbody tr td').hasClass('noresults')) {
      return $('table.users').dataTable({
        bPaginate: false,
        bFilter: false,
        bInfo: false,
        bSort: false,
        sScrollY: 'auto',
        bAutoWidth: true,
        sScrollX: '100%',
      });
    } else {
      return $('.users-table').addClass('table-responsive');
    }
  };

  var _handleScrollTable = () =>
    $(window).load(function () {
      const ua = navigator.userAgent;
      if (
        !/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile|mobile|CriOS/i.test(
          ua,
        )
      ) {
        return $('.users-table .dataTables_scrollBody').niceScroll({
          scrollspeed: 30,
          cursorwidth: 10,
          cursoropacitymax: 0.4,
        });
      }
    });

  var _getUserPath = function () {
    if (
      $('table.users tbody tr').text().trim() === 'No results found' ||
      $('table.users tbody tr').text().trim() === 'មិនមានលទ្ធផល'
    ) {
      return;
    }
    return $('table.users tbody tr').click(function (e) {
      if ($(e.target).hasClass('btn') || $(e.target).hasClass('fa')) {
        return;
      }
      return (window.location = $(this).data('href'));
    });
  };

  return { init: _init };
})();
