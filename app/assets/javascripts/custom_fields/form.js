CIF.Custom_fieldsNew =
  CIF.Custom_fieldsCreate =
  CIF.Custom_fieldsEdit =
  CIF.Custom_fieldsUpdate =
    (function () {
      this.customFieldId = $('#custom_field_id').val();
      const FIELDS_URL = `/api/custom_fields/${this.customFieldId}/fields`;
      const CUSTOM_FIELDS_URL = '/api/custom_fields/fetch_custom_fields';
      const _init = function () {
        _initFormBuilder();
        if ($('#custom_field_id').val() !== '') {
          _retrieveData(FIELDS_URL);
        }
        if ($('#custom_field_form_title').attr('disabled') !== 'disabled') {
          _retrieveData(CUSTOM_FIELDS_URL);
        }
        _select2();
        _toggleTimeOfFrequency();
        _changeSelectOfFrequency();
        _valTimeOfFrequency();
        _changeTimeOfFrequency();
        return _convertFrequency();
      };

      var _valTimeOfFrequency = () => $('#custom_field_time_of_frequency').val();

      let timeOfFrequency = parseInt(_valTimeOfFrequency());

      var _toggleTimeOfFrequency = function () {
        const frequency = _convertFrequency();
        if (frequency === '') {
          $('#custom_field_time_of_frequency').attr('readonly', 'true').val(0);
          return $('.frequency-note').addClass('hidden');
        } else {
          if (timeOfFrequency === 0) {
            timeOfFrequency = 1;
          }
          $('#custom_field_time_of_frequency')
            .removeAttr('readonly')
            .val(parseInt(timeOfFrequency));

          return _updateFrequencyNote(frequency, timeOfFrequency);
        }
      };

      var _changeTimeOfFrequency = () =>
        $('#custom_field_time_of_frequency').change(function () {
          if ($(this).val() === '') {
            $(this).val(1);
          }
          const frequency = _convertFrequency();
          return _updateFrequencyNote(frequency, parseInt($(this).val()));
        });

      var _updateFrequencyNote = function (frequency, timeOfFrequency) {
        if (timeOfFrequency <= 0) {
          return $('.frequency-note').addClass('hidden');
        } else {
          $('.frequency-note').removeClass('hidden');
          if (timeOfFrequency === 1) {
            return $('.frequency-note span.frequency').text(` ${frequency}.`);
          } else {
            return $('.frequency-note span.frequency').text(` ${timeOfFrequency} ${frequency}s.`);
          }
        }
      };

      var _changeSelectOfFrequency = () =>
        $('#custom_field_frequency').change(() => _toggleTimeOfFrequency());

      var _convertFrequency = function () {
        let frequency = $('#custom_field_frequency').val();
        switch (frequency) {
          case 'Daily':
            return (frequency = 'day');
          case 'Weekly':
            return (frequency = 'week');
          case 'Monthly':
            return (frequency = 'month');
          case 'Yearly':
            return (frequency = 'year');
          default:
            return (frequency = '');
        }
      };

      var _initFormBuilder = function () {
        const builderOption = new CIF.CustomFormBuilder();
        const fields = `${$('.build-wrap').data('fields')}` || '';
        const formBuilder = $('.build-wrap')
          .formBuilder({
            dataType: 'json',
            formData: fields.replace(/=>/g, ':'),
            disableFields: ['autocomplete', 'header', 'hidden', 'paragraph', 'button', 'checkbox'],
            showActionButtons: false,
            messages: {
              cannotBeEmpty: 'name_separated_with_underscore',
            },
            stickyControls: {
              enable: true,
              offset: {
                top: 20,
                right: 20,
                left: 'auto',
              },
            },

            typeUserEvents: {
              'checkbox-group': builderOption.eventCheckboxOption(),
              date: builderOption.eventDateOption(),
              file: builderOption.eventFileOption(),
              number: builderOption.eventNumberOption(),
              'radio-group': builderOption.eventRadioOption(),
              select: builderOption.eventSelectOption(),
              text: builderOption.eventTextFieldOption(),
              textarea: builderOption.eventTextAreaOption(),
            },
          })
          .data('formBuilder');

        return $('#custom-field-submit').click((event) =>
          $('#custom_field_fields').val(formBuilder.formData),
        );
      };

      var _select2 = function () {
        CIF.Select.init('#custom_field_entity_type');
        return CIF.Select.init('#custom_field_frequency', { allowClear: true });
      };

      var _retrieveData = (url) =>
        $.ajax({
          method: 'GET',
          url,
          dataType: 'JSON',
          success(response) {
            if (response.hasOwnProperty('fields')) {
              _preventRemoveFields(response.fields);
            }
            if (response.hasOwnProperty('custom_fields')) {
              return _searchCustomFields(response.custom_fields);
            }
          },
        });

      var _searchCustomFields = (fields) =>
        $('#custom_field_form_title').keyup(function () {
          $('#livesearch').css('visibility', 'hidden');
          $('#livesearch').empty();
          const form_title = $('#custom_field_form_title').val();
          if (form_title !== '') {
            return (() => {
              const result = [];
              for (var field of fields) {
                if (field.form_title.toLowerCase().startsWith(form_title.toLowerCase())) {
                  var previewTranslation = $('#livesearch').data('preview-translation');
                  var copyTranslation = $('#livesearch').data('copy-translation');
                  var width = $('#custom_field_form_title').css('width');
                  $('#livesearch').css('width', width);
                  $('#livesearch').css('visibility', 'visible');
                  var ngo_name = field.ngo_name.replace(/\s/g, '+');
                  var url_origin = document.location.origin;
                  var preview_link = `${url_origin}/fields/preview?custom_field_id=${field.id}&ngo_name=${ngo_name}`;
                  // POAM-004 / DOM-XSS fix: build the result row with safe jQuery element construction.
                  // .text() escapes the admin/cross-org form_title + ngo_name (stored-XSS channel); .attr()
                  // sets a properly-quoted href (the old unquoted `href=#{preview_link}` allowed break-out).
                  // No interpolated HTML string reaches the DOM.
                  var $li = $('<li>');
                  $('<span>', { class: 'col-xs-8' })
                    .text(`${field.form_title} (${field.ngo_name})`)
                    .appendTo($li);
                  var $right = $('<span>', { class: 'col-xs-4 text-right' }).appendTo($li);
                  $('<a>').text(previewTranslation).attr('href', preview_link).appendTo($right);
                  result.push($('#livesearch').append($li));
                } else {
                  result.push(undefined);
                }
              }
              return result;
            })();
          }
        });

      var _preventRemoveFields = function (fields) {
        const labelFields = $('label.field-label');
        return (() => {
          const result = [];
          for (var labelField of labelFields) {
            var parent = $(labelField).parent();
            var text = labelField.textContent;
            if (fields.includes(text)) {
              result.push($(parent).children('div.field-actions').remove());
            } else {
              result.push(undefined);
            }
          }
          return result;
        })();
      };

      return { init: _init };
    })();
