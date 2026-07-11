CIF.DashboardsIndex = (function () {
  const _init = function () {
    _clientGenderChart();
    _clientStatusChart();
    _familyType();
    return _resizeChart();
  };

  var _resizeChart = () =>
    $('.minimalize-styl-2').click(() =>
      setTimeout(() => window.dispatchEvent(new Event('resize')), 220),
    );

  var _clientGenderChart = function () {
    const element = $('#client-by-gender');
    const data = $(element).data('content-count');
    if (!element.length || data == null) {
      return;
    }
    const report = new CIF.ReportCreator(data, '', '', element);
    return report.donutChart();
  };

  var _clientStatusChart = function () {
    const element = $('#client-by-status');
    const data = $(element).data('content-count');
    if (!element.length || data == null) {
      return;
    }
    const report = new CIF.ReportCreator(data, '', '', element);
    return report.pieChart();
  };

  var _familyType = function () {
    const element = $('#family-type');
    const data = $(element).data('content-count');
    if (!element.length || data == null) {
      return;
    }
    const report = new CIF.ReportCreator(data, '', '', element);
    return report.pieChart();
  };

  return { init: _init };
})();
