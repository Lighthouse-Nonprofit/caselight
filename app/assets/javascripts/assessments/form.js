CIF.AssessmentsNew =
  CIF.AssessmentsEdit =
  CIF.AssessmentsCreate =
  CIF.AssessmentsUpdate =
    (function () {
      const _init = function () {
        const formid = $('form.assessment-form').attr('id');
        const form = $('#' + formid);

        _formValidate(form);
        _loadSteps(form);
        _addTasks();
        _postTask();
        _addElement();
        _translatePagination();
        _initUploader();
        _handleDeleteAttachment();
        _removeTask();
        _removeHiddenTaskArising();
        return _saveAssessment(form);
      };

      const _handleAppendAddTaskBtn = function () {
        const scores = $('.score_option:visible').find(
          'label.collection_radio_buttons.text-bg-danger, label.collection_radio_buttons.text-bg-warning',
        );
        if ($(scores).length > 0) {
          return $('.assessment-task-btn, .task_required').removeClass('hidden d-none').show();
        } else {
          return $('.assessment-task-btn, .task_required').hide();
        }
      };

      var _translatePagination = function () {
        const next = $('#rootwizard').data('next');
        const previous = $('#rootwizard').data('previous');
        const finish = $('#rootwizard').data('finish');
        const save = $('#rootwizard').data('save');
        $('#rootwizard a[href="#next"]').text(next);
        $('#rootwizard a[href="#previous"]').text(previous);
        $('#rootwizard a[href="#save"]').text(save);
        return $('#rootwizard a[href="#finish"]').text(finish);
      };

      var _addElement = () => $('.actions.clearfix ul').before('<hr/>');

      var _formValidate = function (form) {
        $('.score_option input').attr('required', 'required');
        $('.col-12').on('click', '.score_option label', function () {
          const currentTabLabels = $(this).parents('.score_option').find('label label');
          currentTabLabels.removeClass('active-label');
          $(this).children('label').addClass('active-label');

          $('.score_option').removeClass('is_error');
          const labelColors = 'text-bg-danger text-bg-warning text-bg-primary text-bg-info';
          currentTabLabels.removeClass(labelColors);
          const score = $(this).children('label').text();
          const scoreColor = $(this).parents('.score_option').data(`score-${score}`);
          const domainId = $(this).parents('.score_option').data('domain-id');

          $(this).children('label').addClass(`text-bg-${scoreColor}`);
          if (scoreColor === 'danger' || scoreColor === 'warning') {
            return $(`.domain-${domainId} .assessment-task-btn, .domain-${domainId} .task_required`)
              .removeClass('hidden d-none')
              .show();
          } else {
            return $(
              `.domain-${domainId} .assessment-task-btn, .domain-${domainId} .task_required`,
            ).hide();
          }
        });

        form.validate({ errorElement: 'em' });
        return {
          errorPlacement(error, element) {
            return element.before(error);
          },
        };
      };

      var _loadSteps = (form) =>
        $('#rootwizard').steps({
          headerTag: 'h4',
          bodyTag: 'div',
          transitionEffect: 'slideLeft',
          autoFocus: true,

          onInit(event, currentIndex) {
            _formEdit(currentIndex);
            _appendSaveButton();
            return _handleAppendAddTaskBtn();
          },

          onStepChanging(event, currentIndex, newIndex) {
            if (currentIndex > newIndex) {
              return true;
            }

            form.validate().settings.ignore = ':disabled,:hidden';
            form.valid();
            return _filedsValidator(currentIndex, newIndex);
          },

          onStepChanged(event, currentIndex, priorIndex) {
            _formEdit(currentIndex);
            _handleAppendAddTaskBtn();
            if (currentIndex === 11) {
              return $("#rootwizard a[href='#save']").remove();
            }
          },

          onFinishing(event, currentIndex, newIndex) {
            // BS5-Q3 (latent since a Rails 5.1+ rung): collection_radio_buttons now emits a
            // hidden BLANK input with the group's name (Rails 4.2 did not). Dropping ':hidden'
            // here (deliberate — unvisited steps must validate) made jquery.validate check
            // that blank hidden input FIRST, failing `required` for every CHECKED score group
            // — Done could never submit. Keep validating hidden steps, skip type=hidden.
            form.validate().settings.ignore = ':disabled, input[type="hidden"]';
            form.valid();
            return _filedsValidator(currentIndex, newIndex);
          },

          onFinished() {
            $('.actions a:contains("Done")').removeAttr('href');
            return form.submit();
          },
          labels: {
            finish: 'Done',
          },
        });

      var _appendSaveButton = function () {
        const action = $('#rootwizard').data('action');
        if (action === 'edit') {
          return $('#rootwizard')
            .find('[aria-label=Pagination]')
            .append(
              "<li><a id='btn-save' href='#save' class='btn btn-info' style='background: #21b9bb;'></a></li>",
            );
        }
      };

      var _saveAssessment = (form) =>
        $("#rootwizard a[href='#save']").on('click', function () {
          form.valid();
          return form.submit();
        });

      var _formEdit = function (currentIndex) {
        const currentTab = `#rootwizard-p-${currentIndex}`;
        const scoreOption = $(`${currentTab} .score_option`);
        const chosenScore = scoreOption.find('label input:checked').val();
        const scoreColor = scoreOption.data(`score-${chosenScore}`);
        return scoreOption
          .find(`label label:contains(${chosenScore})`)
          .addClass(`text-bg-${scoreColor}`);
      };

      var _filedsValidator = function (currentIndex, newIndex) {
        const currentTab = `#rootwizard-p-${currentIndex}`;
        const scoreOption = $(`${currentTab} .score_option`);

        if (scoreOption.find('input.error').length) {
          $(currentTab).find('.score_option').addClass('is_error');
          return false;
        } else {
          $(currentTab).find('.score_option').removeClass('is_error');
          if (
            $(currentTab).find('textarea.goal.valid').length &&
            $(currentTab).find('textarea.reason.valid').length
          ) {
            const activeLabel = $(currentTab).find('.active-label');
            const activeScore = activeLabel.text();
            const activeScoreColor = $(activeLabel)
              .parents('.score_option')
              .data(`score-${activeScore}`);

            if (activeScoreColor === 'warning' || activeScoreColor === 'danger') {
              if ($(`${currentTab} ol.tasks-list li`).length >= 1) {
                return true;
              }
            } else {
              return true;
            }
          }
        }
      };

      var _addTasks = () =>
        $('.assessment-task-btn').on('click', function (e) {
          _clearTaskForm();
          const domainId = $(e.target).data('domain-id');
          return $('#task_domain_id').val(domainId);
        });

      var _postTask = () =>
        $('.add-task-btn').on('click', function (e) {
          $('.add-task-btn').attr('disabled', 'disabled');
          e.preventDefault();
          let actionUrl = undefined;
          let data = undefined;
          data = $('#assessment_domain_task').serializeArray();
          actionUrl = $('#assessment_domain_task').attr('action').split('?')[0];

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
              $('.add-task-btn').removeAttr('disabled');
              return _showTaskError(response.responseJSON);
            },
          });
        });

      var _addElementToDom = function (data, actionUrl) {
        const appendElement = $(`.domain-${data.domain_id} .task-arising`);
        let deleteUrl = undefined;
        let element = undefined;
        deleteUrl = `${actionUrl}/${data.id}`;
        element = `<li class='list-group-item' style='padding-bottom: 11px;'>${data.name}<a class='float-end remove-task fa fa-trash btn btn-outline btn-danger btn-xs' href='javascript:void(0)' data-url='${deleteUrl}' style='margin: 0;'></a></li>`;

        $(`.domain-${data.domain_id} .task-arising`).removeClass('hidden d-none');
        $(`.domain-${data.domain_id} .task-arising ol`).append(element);
        _clearTaskForm();

        return $('a.remove-task').on('click', (e) => _deleteTask(e));
      };

      var _removeHiddenTaskArising = function () {
        const tasksList = $('li.list-group-item');
        if ($(tasksList).length > 0) {
          return $(tasksList).parents('.task-arising').removeClass('hidden d-none');
        }
      };

      var _removeTask = () => $('a.remove-task').on('click', (e) => _deleteTask(e));

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

      const _removeTaskError = function () {
        const task = '#assessment_domain_task';
        $(`${task} .task_name, ${task} .task_completion_date`).removeClass('has-error');
        return $(`${task} .task_name_help, ${task} .task_completion_date_help`).hide();
      };

      var _showTaskError = function (error) {
        const task = '#assessment_domain_task';
        if (error.completion_date !== undefined && error.completion_date.length > 0) {
          $(`${task} .task_completion_date`).addClass('has-error');
          $(`${task} .task_completion_date_help`).show().html(error.completion_date[0]);
        } else {
          $(`${task} .task_completion_date`).removeClass('has-error');
          $(`${task} .task_completion_date_help`).hide();
        }

        if (error.name !== undefined && error.name.length > 0) {
          $(`${task} .task_name`).addClass('has-error');
          return $(`${task} .task_name_help`).show().html(error.name[0]);
        } else {
          $(`${task} .task_name`).removeClass('has-error');
          return $(`${task} .task_name_help`).hide();
        }
      };

      var _clearTaskForm = function () {
        _removeTaskError();
        const task = '#assessment_domain_task';
        $(`${task} #task_name`).val('');
        return $(`${task} #task_completion_date`).val('');
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
          const confirmDelete = $(deleteBtn).data('comfirm');
          return $(deleteBtn).click(function () {
            const result = confirm(confirmDelete);
            if (!result) {
              return;
            }
            const BtnURL = $(deleteBtn)[0].dataset.url;
            return $.ajax({
              dataType: 'json',
              url: BtnURL,
              method: 'DELETE',
              success(response) {
                $(element).remove();
                let index = 0;
                const attachments = $('.row-file:visible');
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
