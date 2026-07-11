CIF.Able_screening_questionsNew =
  CIF.Able_screening_questionsCreate =
  CIF.Able_screening_questionsEdit =
  CIF.Able_screening_questionsUpdate =
    (function () {
      const _init = function () {
        _initialSelect2();
        _afterSelectMode();
        // _reloadAfterCocoon()
        return _initUploader();
      };

      var _initialSelect2 = () => CIF.Select.init('.select2');

      var _initUploader = function () {
        const image = $('.question-image img');
        const uploader = $('#able-image');
        const button = $('.browse-image');
        return $(image).previewImage({
          uploader,
          button,
        });
      };

      const _reloadAfterCocoon = () =>
        $('.container-fluid').on('cocoon:after-insert', function (e, insertedItem) {
          CIF.Select.init(insertedItem.find('.select2'));
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

      var _checkModeHandler = function (element, value) {
        let left;
        const parentElement = $(element).closest('.row');
        const checkBoxName = parentElement.find('input[type="checkbox"]').attr('name');
        const checkBoxId = parentElement.find('input[type="checkbox"]').attr('id');
        const disabled = (left = value === 'free_text') != null ? left : { true: false };
        let check = $(`#${checkBoxId}`).val() === '1';
        if (value === 'free_text') {
          check = false;
        }

        return $(`input[name='${checkBoxName}']`).prop('disabled', disabled);
      };

      return { init: _init };
    })();
