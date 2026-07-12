CIF.Custom_field_propertiesNew =
  CIF.Custom_field_propertiesCreate =
  CIF.Custom_field_propertiesEdit =
  CIF.Custom_field_propertiesUpdate =
    (function () {
      const _init = function () {
        _initSelect2();
        _initUploader();
        _handleDeleteAttachment();
        return _preventRequireFileUploader();
      };
      // _handlePreventCheckbox()

      var _initSelect2 = () => CIF.Select.init('select');

      var _initUploader = () =>
        $('.file').fileinput({
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
          const url = $(deleteBtn).data('url');
          const confirmDelete = $(deleteBtn).data('comfirm');
          return $(deleteBtn).click(function () {
            const result = confirm(confirmDelete);
            if (!result) {
              return;
            }
            $('input[type="submit"].form-btn').attr('disabled', 'disabled');
            return $.ajax({
              dataType: 'json',
              url,
              method: 'DELETE',
              success(response) {
                _initNotification(response.message);
                $(element).remove();
                return $('input[type="submit"].form-btn').removeAttr('disabled');
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

      // _handlePreventCheckbox = ->
      //   form = $('form.simple_form')
      //   $(form).on 'submit', (e) ->
      //     checkboxes = $(form).find('input[type="checkbox"]')
      //     otherInputs = $(form).find('input:not([type="checkbox"], [type="file"], [type="hidden"], [type="submit"])')
      //     checked = false
      //
      //     for checkbox in checkboxes
      //       if $(checkbox).prop('checked')
      //         checked = true
      //         break
      //
      //     if checkboxes.length > 0 and !checked and otherInputs.length == 0
      //       e.preventDefault()
      //       $('#message').text("Please select a checkbox")

      var _preventRequireFileUploader = function () {
        const prevent = new CIF.PreventRequiredFileUploader();
        return prevent.preventFileUploader();
      };

      return { init: _init };
    })();
