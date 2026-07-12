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

      var _initSelect2 = function () {
        // pre-Tom-Select this ran as an (ignored) 2nd argument to .select2(), i.e. BEFORE init
        _clearSelectedOption();
        return CIF.Select.init('select', { allowClear: true });
      };

      var _clearSelectedOption = function () {
        const formAction = $('body').attr('id');
        if (!formAction.includes('edit')) {
          return $('#user_roles').val('');
        }
      };

      var _handleDisableManagerField = () =>
        // was select2 v3's 'select2-selected'; Tom Select syncs the native select and
        // dispatches a real change event, so plain change has identical semantics here
        $('#user_roles').on('change', function () {
          if ($(this).val() === 'admin' || $(this).val() === 'strategic overviewer') {
            CIF.Select.setValue('#user_manager_id', '');
            return CIF.Select.disable('#user_manager_id');
          } else {
            return CIF.Select.enable('#user_manager_id');
          }
        });

      // Applies the manager-field state for the CURRENT role at page load. The decaffeinated
      // original called this bare, so $(this) wrapped nothing — silently undefined on jQuery
      // 1-3, a val() TypeError on jQuery 4 (caught by the P6 sweep on /admin/users/new).
      // Read the role select explicitly; the change handler above keeps its own $(this).
      var _disableManagerField = function () {
        const role = $('#user_roles').val();
        if (role === 'admin' || role === 'strategic overviewer') {
          CIF.Select.setValue('#user_manager_id', '');
          return CIF.Select.disable('#user_manager_id');
        } else {
          return CIF.Select.enable('#user_manager_id');
        }
      };

      return { init: _init };
    })();
