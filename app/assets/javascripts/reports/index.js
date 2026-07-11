CIF.ReportsIndex = (function () {
  const _init = () => _rollBackBlankInput();

  var _rollBackBlankInput = () =>
    $('.statistic-search').click((e) =>
      $('.date-picker').each(function () {
        const inputDate = $(this).val();
        if (inputDate === '') {
          e.preventDefault();
          return $(this).addClass('errors');
        } else {
          return $(this).removeClass('errors');
        }
      }),
    );

  return { init: _init };
})();
