CIF.Quarterly_reportsIndex = (function () {
  const _init = () => _getQuarterlyReportPath();

  var _getQuarterlyReportPath = () =>
    $('table.quarterly-reports tbody tr').click(function () {
      return (window.location = $(this).data('href'));
    });

  return { init: _init };
})();
