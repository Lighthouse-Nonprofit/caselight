CIF.Program_streamsIndex = (function () {
  // D2: the CIF.TableScroll calls left with the dataTables/niceScroll retirement — the
  // fixed-header call was already commented out of _init, and hideScrollOnMobile targeted
  // .dataTables_scrollBody, which never existed on this page as a result. Row navigation
  // rides the shared delegated handler.
  const _init = function () {
    CIF.RecordTable.init('table.program-streams', '.program-stream-table');
    return _activeTab();
  };

  var _activeTab = function () {
    const tab = window.location.href.split('tab')[1];
    if (tab === undefined) {
      return;
    }
    if (tab.substr(1) === 'all_ngo') {
      const trigger = document.querySelector('a[href="#ngos-program-streams"]');
      return trigger && bootstrap.Tab.getOrCreateInstance(trigger).show();
    }
  };

  return { init: _init };
})();
