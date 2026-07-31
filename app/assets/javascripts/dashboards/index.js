CIF.DashboardsIndex = (function () {
  // Data-task batch C4: the org charts died with the orphaned @dashboard partials — this
  // page's only JS is the personal 10-day agenda. The org dashboard (admin + strategic
  // overviewer) renders no #dashboard-agenda container, so this is a no-op there.
  const _init = () => _agenda();

  const _agenda = function () {
    const el = document.getElementById('dashboard-agenda');
    if (!el) {
      return;
    }
    const calendar = new FullCalendar.Calendar(el, {
      initialView: 'listTenDay',
      views: { listTenDay: { type: 'list', duration: { days: 10 } } },
      headerToolbar: false,
      height: 'auto',
      // Same task-native feed as the calendar page — bucket colors + client-page urls come free.
      events: (fetchInfo, success, failure) =>
        $.ajax({
          type: 'GET',
          url: '/api/calendars/find_event',
          dataType: 'JSON',
          data: { start: fetchInfo.startStr, end: fetchInfo.endStr },
        })
          .done((events) => success(events || []))
          .fail(() => success([])),
    });
    return calendar.render();
  };

  return { init: _init };
})();
