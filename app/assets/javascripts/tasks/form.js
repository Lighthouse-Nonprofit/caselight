CIF.TasksNew =
  CIF.TasksCreate =
  CIF.TasksEdit =
  CIF.TasksUpdate =
    (function () {
      const _init = function () {
        _initSelect2();
        return _disableButtonSave();
      };

      var _initSelect2 = () => CIF.Select.init('select');

      var _disableButtonSave = () =>
        $('input[type=submit]').on('click', function (e) {
          // was select2 v3's #select2-chosen-1 (the first widget's displayed text);
          // read the underlying domain select directly instead of widget internals
          const domain = CIF.Select.selectedText('#task_domain_id');
          const taskName = $('#task_name').val();
          const taskCompletionDate = $('#task_completion_date').val();
          if (domain !== '' && taskName !== '' && taskCompletionDate !== '') {
            $('input[type=submit]').attr('disabled', 'disabled');
            return $('form.task-form').submit();
          }
        });

      return { init: _init };
    })();
