CIF.TasksNew =
  CIF.TasksCreate =
  CIF.TasksEdit =
  CIF.TasksUpdate =
    (function () {
      const _init = function () {
        _initSelect2();
        return _disableButtonSave();
      };

      var _initSelect2 = () => $('select').select2();

      var _disableButtonSave = () =>
        $('input[type=submit]').on('click', function (e) {
          const domain = $('#select2-chosen-1').text();
          const taskName = $('#task_name').val();
          const taskCompletionDate = $('#task_completion_date').val();
          if (domain !== '' && taskName !== '' && taskCompletionDate !== '') {
            $('input[type=submit]').attr('disabled', 'disabled');
            return $('form.task-form').submit();
          }
        });

      return { init: _init };
    })();
