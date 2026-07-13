CIF.ClientsNew =
  CIF.ClientsCreate =
  CIF.ClientsUpdate =
  CIF.ClientsEdit =
    (function () {
      const _init = function () {
        _ajaxCheckExistClient();
        _clientSelectOption();
        _checkClientBirthdateAvailablity();
        _fixedHeaderStageQuestion();
        return _toggleAnswer();
      };

      var _ajaxCheckExistClient = () =>
        $('#submit-button').on('click', function () {
          const data = {
            given_name: $('#client_given_name').val(),
            family_name: $('#client_family_name').val(),
            local_given_name: $('#client_local_given_name').val(),
            local_family_name: $('#client_local_family_name').val(),
            birth_province_id: $('#client_birth_province_id').val(),
            current_province_id: $('#client_province_id').val(),
            date_of_birth: $('#client_date_of_birth').val(),
            village: $('#client_village').val(),
            commune: $('#client_commune').val(),
          };
          if (
            data.date_of_birth !== '' ||
            data.given_name !== '' ||
            data.birth_province_id !== '' ||
            data.family_name !== '' ||
            data.local_given_name !== '' ||
            data.local_family_name !== '' ||
            data.village !== '' ||
            data.commune !== '' ||
            data.current_province_id !== ''
          ) {
            return $.ajax({
              type: 'GET',
              url: '/api/clients/compare',
              data,
              dataType: 'JSON',
            }).done(function (json) {
              // jQuery-3 prep: jqXHR.success was removed in 3.0
              let client;
              const clientId = $('#client_id').val();
              const clientIds = [];
              const { clients } = json;
              for (client of clients) {
                clientIds.push(String(client.id));
              }

              if (clients.length > 0 && !clientIds.includes(clientId)) {
                const modalTitle = $('#hidden_title').val();
                const modalTextFirst = $('#hidden_body_first').val();
                const modalTextSecond = $('#hidden_body_second').val();
                const modalTextThird = $('#hidden_body_third').val();
                const clientName = $('#client_given_name').val();
                const organizations = [];
                organizations.push(
                  (() => {
                    const result = [];
                    for (client of clients) {
                      result.push(client.organization);
                    }
                    return result;
                  })(),
                );
                // $.unique removed in jQuery 4 (it was DOM-node uniqueSort; this deduped
                // name strings by side effect) — a Set dedupe keeps insertion order
                organizations[0] = [...new Set(organizations[0])];
                const modalText = [];
                for (var organization of organizations[0]) {
                  modalText.push(
                    `<p>${modalTextFirst} ${organization}${modalTextSecond} ${organization} ${modalTextThird}<p/>`,
                  );
                }

                $('#confirm-client-modal .modal-header .modal-title').text(modalTitle);
                $('#confirm-client-modal .modal-body').html(modalText);

                bootstrap.Modal.getOrCreateInstance(
                  document.getElementById('confirm-client-modal'),
                ).show();
                return $('#confirm-client-modal #confirm').on('click', () =>
                  $('form.client-form').submit(),
                );
              } else {
                return $('form.client-form').submit();
              }
            });
          } else {
            return $('form.client-form').submit();
          }
        });

      var _clientSelectOption = function () {
        // pre-Tom-Select _clearSelectedOption() ran as an (ignored) 2nd argument, i.e. BEFORE init
        _clearSelectedOption();
        CIF.Select.init('select', { allowClear: true });

        return $('select.able-related-info').change(function () {
          const qtSelectedSize = $('select.able-related-info option:selected').length;

          if (qtSelectedSize > 0) {
            $('#client_able').val(true);
            return $('#fake_client_able').prop('checked', true);
          } else {
            $('#client_able').val(false);
            return $('#fake_client_able').prop('checked', false);
          }
        });
      };

      var _clearSelectedOption = function () {
        const formAction = $('body').attr('id');
        if (!formAction.includes('edit')) {
          return $('#client_gender').val('');
        }
      };

      var _fixedHeaderStageQuestion = () =>
        $('#stage-question table.client-new').dataTable({
          sScrollY: '500px',
          sScrollX: '100%',
          bPaginate: false,
          bFilter: false,
          bInfo: false,
          bSort: false,
          bAutoWidth: true,
        });

      const _arrangeQuestionAndAnswerBlock = function () {
        const questionsAndAnswers = $('.question_and_answer');
        return (() => {
          const result = [];
          for (var questionAndAnswer of questionsAndAnswers) {
            var html;
            var qa = $(questionAndAnswer);
            if (qa.data('is-stage')) {
              html = qa.html();
              $('#stage-question').append(html);
              result.push(qa.remove());
            } else {
              html = qa.html();
              $('#non-stage-question').append(html);
              result.push(qa.remove());
            }
          }
          return result;
        })();
      };

      var _checkClientBirthdateAvailablity = function () {
        const button = $('#able-screening-test');
        if ($('#client_date_of_birth').val() === '') {
          button.attr('disabled', 'disabled');
        }
        return $('#client_date_of_birth').change(function () {
          if ($('#client_date_of_birth').val() === '') {
            return button.attr('disabled', 'disabled');
          } else {
            button.removeAttr('disabled');
            return _toggleAnswer();
          }
        });
      };

      const _getAge = function (dateString) {
        const today = new Date();
        const birthDate = new Date(dateString);
        let age = today.getFullYear() - birthDate.getFullYear();
        const m = today.getMonth() - birthDate.getMonth();
        if (m < 0 || (m === 0 && today.getDate() < birthDate.getDate())) {
          age--;
        }
        return age;
      };

      var _toggleAnswer = function () {
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

      window.onload = function () {
        const ua = navigator.userAgent;
        if (
          !/Android|webOS|iPhone|iPad|iPod|BlackBerry|IEMobile|Opera Mini|Mobile|mobile|CriOS/i.test(
            ua,
          )
        ) {
          return $(
            '#stage-question.table-responsive, #stage-question .dataTables_scrollBody',
          ).niceScroll({
            scrollspeed: 30,
            cursorwidth: 10,
            cursoropacitymax: 0.4,
          });
        }
      };

      return { init: _init };
    })();
