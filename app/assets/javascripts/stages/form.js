CIF.StagesNew =
  CIF.StagesCreate =
  CIF.StagesEdit =
  CIF.StagesUpdate =
    (function () {
      const _init = function () {
        _initialSelect2();
        _afterSelectMode();
        _reloadAfterCocoon();
        _validateInputNumber();
        return _initEditUploader();
      };

      var _initialSelect2 = () =>
        $('.select2').select2({
          theme: 'bootstrap',
        });

      var _initEditUploader = () =>
        $('.nested-fields').each(function () {
          return _initUploader(this);
        });

      var _initUploader = function (questionRow) {
        const image = $(questionRow).find('.question-image img');
        const uploader = $(questionRow).find('.stage-image');
        const button = $(questionRow).find('.browse-image');
        return $(image).previewImage({
          uploader,
          button,
        });
      };

      var _reloadAfterCocoon = () =>
        $('#page-wrapper').on('cocoon:after-insert', function (e, insertedItem) {
          const newImageId = +new Date();
          insertedItem.find('.select2').select2({
            theme: 'bootstrap',
          });
          _initUploader(insertedItem);
          return _afterSelectMode();
        });

      var _afterSelectMode = function () {
        const self = this;
        $('.check-mode').map(function (index) {
          const element = $($('.check-mode')[index]);
          return _checkModeHandler(element, element.val());
        });

        return $('.check-mode').on('change', function (e, item) {
          return _checkModeHandler(this, e.val);
        });
      };

      var _validateInputNumber = () =>
        $('#stage_from_age,#stage_to_age').keydown(function (e) {
          if (
            $.inArray(e.keyCode, [46, 8, 9, 27, 13, 110, 190]) !== -1 ||
            (e.keyCode === 65 && e.ctrlKey === true) ||
            (e.keyCode === 67 && e.ctrlKey === true) ||
            (e.keyCode === 88 && e.ctrlKey === true) ||
            (e.keyCode >= 35 && e.keyCode <= 41)
          ) {
            return;
          }
          if (
            (e.shiftKey || e.keyCode < 48 || e.keyCode > 57) &&
            (e.keyCode < 96 || e.keyCode > 105)
          ) {
            e.preventDefault();
          }
        });

      var _checkModeHandler = function (element, value) {
        const parentElement = $(element).closest('.row');
        const checkBoxName = parentElement.find('input[type="checkbox"]').attr('name');
        const checkBoxId = parentElement.find('input[type="checkbox"]').attr('id');
        const disabled = value === 'free_text' ? true : false;
        let check = $(`#${checkBoxId}`).val() === '1';
        if (value === 'free_text') {
          check = false;
        }

        return $(`input[name='${checkBoxName}']`).prop('disabled', disabled);
      };

      return { init: _init };
    })();
