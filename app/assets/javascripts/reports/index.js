// Investor UX round (2026-07): the Reports landing page. The two chart creators moved here
// VERBATIM from clients/index.js (the charts left clients#index); the div-id + data-attribute
// contract is unchanged. The old CIF.ReportsIndex body (_rollBackBlankInput) targeted the
// pre-2020 reports controller's date-range form — dead markup, dropped.
CIF.ReportsIndex = (function () {
  const _init = function () {
    _handleCreateCsiDomainReport();
    _handleCreateCaseReport();
    _clickMenuResizeChart();
  };

  var _handleCreateCsiDomainReport = function () {
    const element = $('#cis-domain-score');
    const csiData = element.data('csi-domain');
    const csiTitle = element.data('title');
    const csiyAxisTitle = element.data('yaxis-title');

    const report = new CIF.ReportCreator(csiData, csiTitle, csiyAxisTitle, element);
    return report.lineChart();
  };

  // R8: enrollments-by-program replaced the EC/FC/KC case chart (flavor-correct
  // in both verticals — program names come from the tenant's own seeds).
  var _handleCreateCaseReport = function () {
    const element = $('#enrollment-statistic');
    const data = element.data('enrollment-statistic');
    const title = element.data('title');
    const yAxisTitle = element.data('yaxis-title');

    const report = new CIF.ReportCreator(data, title, yAxisTitle, element);
    return report.lineChart();
  };

  // Sidebar collapse/expand changes the chart column width — nudge Chart.js to re-measure.
  var _clickMenuResizeChart = () =>
    $('.minimalize-styl-2').click(() => setTimeout(() => _handleResizeWindow(), 220));

  var _handleResizeWindow = () => window.dispatchEvent(new Event('resize'));

  return { init: _init };
})();
