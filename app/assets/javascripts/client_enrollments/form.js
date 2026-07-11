CIF.Client_enrollmentsNew =
  CIF.Client_enrollmentsCreate =
  CIF.Client_enrollmentsEdit =
  CIF.Client_enrollmentsUpdate =
  CIF.Client_enrolled_programsNew =
  CIF.Client_enrolled_programsCreate =
  CIF.Client_enrolled_programsEdit =
  CIF.Client_enrolled_programsUpdate =
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
          theme: 'explorer',
          allowedFileExtensions: ['jpg', 'png', 'jpeg', 'doc', 'docx', 'xls', 'xlsx', 'pdf'],
        });

      var _preventRequireFileUploader = function () {
        const prevent = new CIF.PreventRequiredFileUploader();
        return prevent.preventFileUploader();
      };

      return { init: _init };
    })();
