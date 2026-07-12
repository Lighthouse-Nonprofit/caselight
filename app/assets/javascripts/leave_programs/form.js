CIF.Leave_programsNew =
  CIF.Leave_programsCreate =
  CIF.Leave_programsEdit =
  CIF.Leave_programsUpdate =
  CIF.Leave_enrolled_programsNew =
  CIF.Leave_enrolled_programsCreate =
  CIF.Leave_enrolled_programsEdit =
  CIF.Leave_enrolled_programsUpdate =
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
