CIF.Case_notesNew =
  CIF.Case_notesCreate =
  CIF.Case_notesEdit =
  CIF.Case_notesUpdate =
    (function () {
      const _init = function () {
        _initUploader();
        _handleDeleteAttachment();
        _handleNewTask();
        _hideCompletedTasks();
        return _handlePreventBlankInput();
      };

      var _initUploader = () =>
        $('.file .optional').fileinput({
          showUpload: false,
          removeClass: 'btn btn-danger btn-outline',
          browseLabel: 'Browse',
          theme: 'explorer-fa4',
          allowedFileExtensions: ['jpg', 'png', 'jpeg', 'doc', 'docx', 'xls', 'xlsx', 'pdf'],
        });

      var _handleDeleteAttachment = function () {
        const rows = $('.row-file');
        return $(rows).each(function (_k, element) {
          const deleteBtn = $(element).find('.delete');
          const attachments = element.parentElement.getElementsByTagName('tr');
          const confirmDelete = $(deleteBtn).data('comfirm');
          return $(deleteBtn).click(function () {
            const result = confirm(confirmDelete);
            if (!result) {
              return;
            }
            const { url } = $(deleteBtn)[0].dataset;
            return $.ajax({
              dataType: 'json',
              url,
              method: 'DELETE',
              success(response) {
                $(element).remove();
                let index = 0;
                if (attachments.length > 0) {
                  for (var td of attachments) {
                    td.getElementsByClassName('delete')[0].dataset.url = _replaceUrlParam(
                      td.getElementsByClassName('delete')[0].dataset.url,
                      'file_index',
                      index++,
                    );
                  }
                }
                return _initNotification(response.message);
              },
            });
          });
        });
      };

      var _hideCompletedTasks = () =>
        $('input.task').each(function () {
          if ($(this).data('completed')) {
            return $(this).parents('span.checkbox').addClass('hidden');
          }
        });

      var _handleNewTask = function () {
        _addTaskToServer();
        return _addDomainToSelect();
      };

      const _showError = function (error) {
        if (error.completion_date !== undefined && error.completion_date.length > 0) {
          $('#case_note_task .task_completion_date').addClass('has-error');
        } else {
          $('#case_note_task .task_completion_date').removeClass('has-error');
        }

        if (error.name !== undefined && error.name.length > 0) {
          return $('#case_note_task .task_name').addClass('has-error');
        } else {
          return $('#case_note_task .task_name').removeClass('has-error');
        }
      };

      var _addTaskToServer = () => _postTask();

      var _postTask = () =>
        $('.add-task-btn').on('click', function (e) {
          $('.add-task-btn').attr('disabled', 'disabled');
          let actionUrl = undefined;
          let data = undefined;
          data = $('#case_note_task').serializeArray();
          actionUrl = $('#case_note_task').attr('action').split('?')[0];
          return $.ajax({
            type: 'POST',
            url: `${actionUrl}.json`,
            data,
            success(response) {
              _addElementToDom(response, actionUrl);
              $('.add-task-btn').removeAttr('disabled');
              var _tfm = document.getElementById('tasksFromModal');
              return _tfm && bootstrap.Modal.getOrCreateInstance(_tfm).hide();
            },
            error(response) {
              _showError(response.responseJSON);
              return $('.add-task-btn').removeAttr('disabled');
            },
          });
        });

      var _addElementToDom = function (data, actionUrl) {
        const appendElement = $(`#tasks-domain-${data.domain_id} .task-arising`);
        let deleteUrl = undefined;
        let element = undefined;
        deleteUrl = `${actionUrl}/${data.id}`;

        element = `<li class='list-group-item' style='padding-bottom: 11px;'>${data.name}<a class='float-end remove-task fa fa-trash btn btn-outline btn-danger btn-xs' style='margin: 0;' href='javascript:void(0)' data-url='${deleteUrl}'></a></li>`;

        if ($(`.task-domain-${data.domain_id}`).hasClass('hidden')) {
          $(`.task-domain-${data.domain_id}`).removeClass('hidden');
        }

        $(`#tasks-domain-${data.domain_id} .task-arising`).removeClass('hidden');
        $(`#tasks-domain-${data.domain_id} .task-arising ol`).append(element);
        _clearForm();

        return $('a.remove-task').on('click', (e) => _deleteTask(e));
      };

      var _clearForm = function () {
        _removeError();
        $('#task_name').val('');
        $('#task_completion_date').val('');

        // POAM-017g flip: vanillajs-datepicker via the shared adapter (was bootstrap-datepicker).
        return $('.task_completion_date').each(function () {
          var dp = CIF.DatePicker.attach(this);
          if (dp) dp.setDate({ clear: true });
        });
      };

      var _removeError = function () {
        $('#case_note_task .task_name').removeClass('has-error');
        return $('#case_note_task .task_completion_date').removeClass('has-error');
      };

      var _deleteTask = function (e) {
        let url = $(e.target).data('url').split('?')[0];
        url = `${url}.json`;

        $.ajax({
          type: 'delete',
          url,
          success(response) {},
        });
        return $(e.target).parent().remove();
      };

      var _addDomainToSelect = () =>
        $('.case-note-task-btn').on('click', function (e) {
          _clearForm();
          const domains = $(e.target).data('domains');
          $('#task_domain_id').html('');

          return domains.map((domain) =>
            $('#task_domain_id').append(`<option value='${domain[0]}'>${domain[1]}</option>`),
          );
        });

      var _handlePreventBlankInput = () =>
        $('#case-note-submit-btn').click(function () {
          const case_note_meeting_date = $('#case_note_meeting_date').val();
          const case_note_attendee = $('#case_note_attendee').val();
          if (case_note_meeting_date === '') {
            document.getElementById('new_case_note').onsubmit = () => false;
            $('.case_note_meeting_date').addClass('has-error');
            $('#meeting-date-message').text("can't be blank");
          } else {
            if (case_note_attendee !== '') {
              document.getElementById('new_case_note').onsubmit = () => true;
            }
            $('.case_note_meeting_date').removeClass('has-error');
            $('#meeting-date-message').text('');
          }
          if (case_note_attendee === '') {
            document.getElementById('new_case_note').onsubmit = () => false;
            $('.case_note_attendee').addClass('has-error');
            return $('#attendee-message').text("can't be blank");
          } else {
            if (case_note_meeting_date !== '') {
              document.getElementById('new_case_note').onsubmit = () => true;
            }
            $('.case_note_attendee').removeClass('has-error');
            return $('#attendee-message').text('');
          }
        });

      var _initNotification = function (message) {
        const messageOption = {
          closeButton: true,
          debug: true,
          progressBar: true,
          positionClass: 'toast-top-center',
          showDuration: '400',
          hideDuration: '1000',
          timeOut: '7000',
          extendedTimeOut: '1000',
          showEasing: 'swing',
          hideEasing: 'linear',
          showMethod: 'fadeIn',
          hideMethod: 'fadeOut',
        };
        return toastr.success(message, '', messageOption);
      };

      var _replaceUrlParam = function (url, paramName, paramValue) {
        if (paramValue === null) {
          paramValue = '';
        }
        const pattern = new RegExp('\\b(' + paramName + '=).*?(&|$)');
        if (url.search(pattern) >= 0) {
          return url.replace(pattern, '$1' + paramValue + '$2');
        }
        return url + (url.indexOf('?') > 0 ? '&' : '?') + paramName + '=' + paramValue;
      };

      return { init: _init };
    })();
