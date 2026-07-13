CIF.Program_streamsIndex = (function () {
  const _init = function () {
    _getFamilyPath();
    // _fixedHeaderTableColumns()
    _handleScrollTable();
    return _activeTab();
  };

  const _fixedHeaderTableColumns = function () {
    const table = $('.program-stream-table');
    return new CIF.TableScroll(table).fixedHeaderTable();
  };

  var _handleScrollTable = () => new CIF.TableScroll('').hideScrollOnMobile();

  var _getFamilyPath = () =>
    $('table.program-streams tbody tr').click(function (e) {
      if ($(e.target).hasClass('btn') || $(e.target).hasClass('fa')) {
        return;
      }
      return (window.location = $(this).data('href'));
    });

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
