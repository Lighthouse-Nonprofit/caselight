CIF.UsersNew =
  CIF.UsersCreate =
  CIF.UsersEdit =
  CIF.UsersUpdate =
    (function () {
      const _init = function () {
        _initSelect2();
        _handleDisableManagerField();
        return _disableManagerField();
      };

      var _initSelect2 = () => $('select').select2({ allowClear: true }, _clearSelectedOption());

      var _clearSelectedOption = function () {
        const formAction = $('body').attr('id');
        if (!formAction.includes('edit')) {
          return $('#user_roles').val('');
        }
      };

      var _handleDisableManagerField = () =>
        $('#user_roles').on('select2-selected', function () {
          if ($(this).val() === 'admin' || $(this).val() === 'strategic overviewer') {
            $('#user_manager_id').select2('val', '');
            return $('#user_manager_id').attr('disabled', 'disabled');
          } else {
            return $('#user_manager_id').removeAttr('disabled');
          }
        });

      var _disableManagerField = function () {
        if ($(this).val() === 'admin' || $(this).val() === 'strategic overviewer') {
          $('#user_manager_id').select2('val', '');
          return $('#user_manager_id').attr('disabled', 'disabled');
        } else {
          return $('#user_manager_id').removeAttr('disabled');
        }
      };

      return { init: _init };
    })();
