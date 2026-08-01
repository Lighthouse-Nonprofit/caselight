// Reports batch (R4) — chart bootstrap for report show pages. Sections that carry
// a chart payload render a div with data-report-chart ([labels, series] in the
// CIF.ReportCreator contract), data-chart-type, and data-title. Same class API
// the landing page uses (new ReportCreator(data, title, yAxisTitle, element)).
CIF.ReportsShow = (function () {
  const _init = function () {
    $('[data-report-chart]').each(function () {
      const element = $(this);
      const data = element.data('report-chart');
      if (!data) return;
      const report = new CIF.ReportCreator(data, element.data('title') || '',
        element.data('yaxis-title') || '', element);
      if (element.data('chart-type') === 'pie') {
        report.pieChart();
      } else {
        report.lineChart();
      }
    });
    // Sidebar collapse changes the chart column width — re-measure (landing-page pattern).
    $('.minimalize-styl-2').click(() => setTimeout(() => window.dispatchEvent(new Event('resize')), 220));
  };

  return { init: _init };
})();
