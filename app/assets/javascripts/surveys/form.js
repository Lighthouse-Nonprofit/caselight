CIF.SurveysNew =
  CIF.SurveysCreate =
  CIF.SurveysEdit =
  CIF.SurveysUpdate =
    (function () {
      const _init = () => _rollbackBlankInput();

      var _rollbackBlankInput = () =>
        $('.survey-submit').click((e) =>
          $('.question-block').each(function () {
            const radioChecked = $(this).find('input[type="radio"]:checked');
            if (radioChecked.length < 1) {
              e.preventDefault();
              return $(this).addClass('errors');
            } else {
              return $(this).removeClass('errors');
            }
          }),
        );

      return { init: _init };
    })();
