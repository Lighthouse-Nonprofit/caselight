CIF.Client_enrollment_trackingsNew =
  CIF.Client_enrollment_trackingsCreate =
  CIF.Client_enrollment_trackingsEdit =
  CIF.Client_enrollment_trackingsUpdate =
  CIF.Client_enrolled_program_trackingsUpdate =
  CIF.Client_enrolled_program_trackingsNew =
  CIF.Client_enrolled_program_trackingsCreate =
  CIF.Client_enrolled_program_trackingsEdit =
    (function () {
      const _init = function () {
        _initSelect2();
        _initFileInput();
        return _preventRequireFileUploader();
      };

      var _initSelect2 = () => CIF.Select.init('select');

      var _initFileInput = () =>
        $('.file').fileinput({
          showUpload: false,
          removeClass: 'btn btn-danger btn-outline',
          browseLabel: 'Browse',
          theme: 'explorer-fa4',
          allowedFileExtensions: ['jpg', 'png', 'jpeg', 'doc', 'docx', 'xls', 'xlsx', 'pdf'],
        });

      var _preventRequireFileUploader = function () {
        const prevent = new CIF.PreventRequiredFileUploader();
        return prevent.preventFileUploader();
      };

      return { init: _init };
    })();
