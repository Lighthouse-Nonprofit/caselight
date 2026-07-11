CIF.Able_screening_answersNew =
  CIF.Able_screening_answersCreate =
  CIF.Able_screening_answersEdit =
  CIF.Able_screening_answersUpdate =
    (function () {
      const _init = () => _removeClassDisabled();

      const _toggleAnswer = function () {
        const answers = $('.answer');
        return (() => {
          const result = [];
          for (var answer of answers) {
            var answerObj = $(answer);
            if (answerObj.data('is-stage') === false) {
              answerObj.find('input').removeAttr('disabled');
              result.push(answerObj.show());
            } else {
              var middle;
              if (
                answerObj.data('to-age') !== '' &&
                answerObj.data('from-age') >= (middle = $('#client_date_of_birth').val()) &&
                middle >= answerObj.data('to-age')
              ) {
                answerObj.find('input').removeAttr('disabled');
                answerObj.show();
                result.push(answerObj.removeClass('disable-qa'));
              } else {
                answerObj.addClass('disable-qa');
                answerObj.find('input').attr('disabled', true);
                result.push(answerObj.hide());
              }
            }
          }
          return result;
        })();
      };

      var _removeClassDisabled = () => $('.client_answers_description').removeClass('disabled');

      return { init: _init };
    })();
