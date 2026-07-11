CIF.TableScroll = class TableScroll {
  constructor(table) {
    this.table = table;
  }

  fixedHeaderTable() {
    return $(this.table).dataTable({
      sScrollY: '500',
      sScrollX: '100%',
      bPaginate: false,
      bFilter: false,
      bInfo: false,
      bSort: false,
      bAutoWidth: true,
    });
  }

  hideScrollOnMobile() {
    return $(window).on('load', function () {
      const ua = navigator.userAgent;
      if (
        !/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile|mobile|CriOS/i.test(
          ua,
        )
      ) {
        return $('.dataTables_scrollBody').niceScroll({
          scrollspeed: 30,
          cursorwidth: 10,
          cursoropacitymax: 0.4,
        });
      }
    });
  }
};
