CIF.Progress_notesIndex = (function () {
  const _init = function () {
    _select2();
    _fixedHeaderTableColumns();
    _handleScrollTable();
    return _getProgressNotePath();
  };

  var _select2 = () => CIF.Select.init('select', { allowClear: true });

  var _fixedHeaderTableColumns = function () {
    $('.progress_notes-table').removeClass('table-responsive');
    if (!$('table.progress-notes tbody tr td').hasClass('noresults')) {
      return $('table.progress-notes').dataTable({
        bPaginate: false,
        bFilter: false,
        bInfo: false,
        bSort: false,
        sScrollY: 'auto',
        bAutoWidth: true,
        sScrollX: '100%',
      });
    } else {
      return $('.progress_notes-table').addClass('table-responsive');
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
        return $('.progress_notes-table .dataTables_scrollBody').niceScroll({
          scrollspeed: 30,
          cursorwidth: 10,
          cursoropacitymax: 0.4,
        });
      }
    });

  var _getProgressNotePath = () =>
    $('table.progress-notes tbody tr').click(function (e) {
      if ($(e.target).hasClass('btn') || $(e.target).hasClass('fa')) {
        return;
      }
      return (window.location = $(this).data('href'));
    });

  return { init: _init };
})();
