CIF.ClientsShow = (function () {
  const _init = function () {
    _rejectModal();
    _exitModalValidate();
    _exitNgoValidator();
    return _initSelect2();
  };

  var _initSelect2 = () => CIF.Select.init('select');

  var _rejectModal = function () {
    const note = $('#client_rejected_note').val();
    if (note === '') {
      $('.confirm-reject').attr('disabled', 'disabled');
    }
    return _rejectFormValidate();
  };

  var _rejectFormValidate = () =>
    $('#client_rejected_note').keyup(function () {
      const note = $('#client_rejected_note').val();
      if (note === '') {
        return $('.confirm-reject').attr('disabled', 'disabled');
      } else {
        return $('.confirm-reject').removeAttr('disabled');
      }
    });

  var _exitNgoValidator = function () {
    const exitDate = $('#exitFromNgo #client_exit_date');
    const exitNote = $('#exitFromNgo #client_exit_note');
    const formId = $('#exitFromNgo');

    _validateExitButton(formId, exitDate, exitNote);

    return $(exitDate)
      .add(exitNote)
      .on('keyup change', () => _validateExitButton(formId, exitDate, exitNote));
  };

  var _exitModalValidate = function () {
    const exitDate = $('#case_exit_date');
    const exitNote = $('#case_exit_note');
    const formId = $('#exit-from-case');

    _validateExitButton(formId, exitDate, exitNote);

    return $(exitDate)
      .add(exitNote)
      .on('keyup change', () => _validateExitButton(formId, exitDate, exitNote));
  };

  var _validateExitButton = function (formId, exitDate, exitNote) {
    exitDate = $(exitDate).val();
    exitNote = $(exitNote).val();

    if (exitNote === '' || exitDate === '') {
      return $(formId).find('.confirm-exit').attr('disabled', 'disabled');
    } else {
      return $(formId).find('.confirm-exit').removeAttr('disabled');
    }
  };

  return { init: _init };
})();
