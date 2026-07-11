CIF.Program_streamsNew =
  CIF.Program_streamsEdit =
  CIF.Program_streamsCreate =
  CIF.Program_streamsUpdate =
    (function () {
      this.programStreamId = $('#program_stream_id').val();
      const ENROLLMENT_URL = `/api/program_streams/${this.programStreamId}/enrollment_fields`;
      const EXIT_PROGRAM_URL = `/api/program_streams/${this.programStreamId}/exit_program_fields`;
      const TRACKING_URL = `/api/program_streams/${this.programStreamId}/tracking_fields`;
      this.formBuilder = [];
      const _init = function () {
        this.filterTranslation = '';
        _getTranslation();
        _initProgramSteps();
        _initCheckbox();
        _addFooterForSubmitForm();
        _handleInitProgramRules();
        _addRuleCallback();
        _initSelect2();
        _handleAddCocoon();
        _handleRemoveCocoon();
        _handleInitProgramFields();
        _initButtonSave();
        _handleSaveProgramStream();
        _handleClickAddTracking();
        _handleShowTracking();
        _handleHideTracking();
        _initSelect2TimeOfFrequency();
        _handleRemoveFrequency();
        _handleSelectFrequency();
        _initFrequencyNote();
        return _editTrackingFormName();
      };

      var _initCheckbox = function () {
        $('.i-checks').iCheck({
          checkboxClass: 'icheckbox_square-green',
        });
        return $($('.icheckbox_square-green.checked')[0]).removeClass('checked');
      };

      const _stickyFill = function () {
        if ($('.form-wrap').is(':visible')) {
          return $('.cb-wrap').Stickyfill();
        }
      };

      var _initSelect2 = () => $('#description select, #rule-tab select').select2();

      var _initSelect2TimeOfFrequency = () =>
        $('.program_stream_trackings_frequency select').select2({
          minimumInputLength: 0,
          allowClear: true,
        });

      const _handleRemoveProgramList = function () {
        const programExclusive = $('#program_stream_program_exclusive');
        const mutualDependence = $('#program_stream_mutual_dependence');
        _selectOptonProgramExclusive(programExclusive, mutualDependence);
        return _selectOptonMutualDependence(programExclusive, mutualDependence);
      };

      var _selectOptonProgramExclusive = function (programExclusive, mutualDependence) {
        if ($(programExclusive).val() !== null) {
          for (var value of $(programExclusive).val()) {
            $(mutualDependence).find(`option[value=${value}]`).attr('disabled', true);
          }
        }

        $(programExclusive).on('select2-selecting', (select) =>
          $(mutualDependence).find(`option[value=${select.val}]`).attr('disabled', true),
        );

        return $(programExclusive).on('select2-removed', (select) =>
          $(mutualDependence).find(`option[value=${select.val}]`).removeAttr('disabled'),
        );
      };

      var _selectOptonMutualDependence = function (programExclusive, mutualDependence) {
        if ($(mutualDependence).val() !== null) {
          for (var value of mutualDependence.val()) {
            $(programExclusive).find(`option[value=${value}]`).attr('disabled', true);
          }
        }

        $(mutualDependence).on('select2-selecting', (select) =>
          $(programExclusive).find(`option[value=${select.val}]`).attr('disabled', true),
        );

        return $(mutualDependence).on('select2-removed', (select) =>
          $(programExclusive).find(`option[value=${select.val}]`).removeAttr('disabled'),
        );
      };

      const _handleSelectTab = function () {
        const tab = $('.program-steps').data('tab');
        return $('li[role="tab"]').each(function () {
          const tabNumber = $(this).find('span.number').text()[0];
          if (parseInt(tabNumber) === tab) {
            $(this).removeClass('disabled');
            return $(this).find('a').trigger('click');
          } else if (parseInt(tabNumber) < tab) {
            $(this).removeClass('disabled');
            return $(this).addClass('done');
          }
        });
      };

      var _handleSaveProgramStream = () =>
        $('#btn-save-draft').on('click', function () {
          if (!_handleCheckingDuplicateFields()) {
            return false;
          }
          if (_handleMaximumProgramEnrollment()) {
            return false;
          }
          _handleRemoveUnuseInput();
          _handleAddRuleBuilderToInput();
          _handleSetValueToField();
          $('.tracking-builder').find('input, textarea').removeAttr('required');
          return $('#program-stream').submit();
        });

      const _handleSetRules = function () {
        let rules = $('#program_stream_rules').val();
        rules = JSON.parse(rules.replace(/=>/g, ':'));
        if (!$.isEmptyObject(rules)) {
          return $('#program-rule').queryBuilder('setRules', rules);
        }
      };

      var _addRuleCallback = () =>
        $('#program-rule').on('afterCreateRuleFilters.queryBuilder', function () {
          _initSelect2();
          return _handleSelectOptionChange();
        });

      var _getTranslation = function () {
        return (this.filterTranslation = {
          addFilter: $('#program-rule').data('filter-translation-add-filter'),
          addGroup: $('#program-rule').data('filter-translation-add-group'),
          deleteGroup: $('#program-rule').data('filter-translation-delete-group'),
          next: $('.program-steps').data('next'),
          previous: $('.program-steps').data('previous'),
          save: $('.program-steps').data('save'),
        });
      };

      var _handleSelectOptionChange = () =>
        $('select').on('select2-selecting', (e) =>
          setTimeout(
            () =>
              $('.rule-operator-container select, .rule-value-container select').select2({
                width: '180px',
              }),
            100,
          ),
        );

      var _handleInitProgramRules = () =>
        $.ajax({
          url: '/api/program_stream_add_rule/get_fields',
          method: 'GET',
          success(response) {
            const fieldList = response.program_stream_add_rule;
            const builder = new CIF.AdvancedFilterBuilder(
              $('#program-rule'),
              fieldList,
              filterTranslation,
            );
            builder.initRule();
            setTimeout(function () {
              _handleSelectTab();
              return _initSelect2();
            }, 100);
            _handleSetRules();
            return _handleSelectOptionChange();
          },
        });

      var _handleAddCocoon = () =>
        $('#trackings').on('cocoon:after-insert', function (e, element) {
          const trackingBuilder = $(element).find('.tracking-builder');
          _initProgramBuilder(trackingBuilder, []);
          _stickyFill();
          _editTrackingFormName();
          _handleRemoveCocoon();
          _initSelect2TimeOfFrequency();
          _handleRemoveFrequency();
          _handleSelectFrequency();
          return _initFrequencyNote();
        });

      var _initProgramBuilder = function (element, data) {
        const builderOption = new CIF.CustomFormBuilder();
        data = data.length !== 0 ? data.replace(/=>/g, ':') : '';
        return this.formBuilder.push(
          $(element)
            .formBuilder({
              dataType: 'json',
              formData: data,
              disableFields: [
                'autocomplete',
                'header',
                'hidden',
                'paragraph',
                'button',
                'checkbox',
              ],
              showActionButtons: false,
              messages: {
                cannotBeEmpty: 'name_separated_with_underscore',
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
            .data('formBuilder'),
        );
      };

      var _editTrackingFormName = function () {
        const inputNames = $(".program_stream_trackings_name input[type='text']");
        return $(inputNames).on('change', () => _checkDuplicateTrackingName());
      };

      var _checkDuplicateTrackingName = function () {
        const nameFields = $('.program_stream_trackings_name:visible input[type="text"]');
        const values = $(nameFields)
          .map(function () {
            return $(this).val().trim();
          })
          .get();

        const duplicateValues = Object.values(values.getDuplicates());
        const indexs = [].concat.apply([], duplicateValues);

        const noneDuplicates = values.elementWitoutDuplicates();
        return $(nameFields).each(function (index, element) {
          const inputWrapper = $(element).parent();
          if (indexs.includes(index)) {
            $(element).addClass('error');
            if (!$(inputWrapper).find('label.error').is(':visible')) {
              return $(inputWrapper).append(
                '<label class="error">Tracking name must be unique</label>',
              );
            }
          } else if (noneDuplicates.includes($(element).val())) {
            $(element).removeClass('error');
            if ($(inputWrapper).find('label.error').is(':visible')) {
              return $(inputWrapper).find('label.error').remove();
            }
          }
        });
      };

      var _handleRemoveCocoon = () =>
        $('#trackings').on('cocoon:after-remove', () => _checkDuplicateTrackingName());

      var _handleCheckingDuplicateFields = function () {
        // jQuery-3 prep: .size() was removed in 3.0; .length is identical on 1.x.
        const errorNumber = $('.form-wrap.form-builder:visible').find('.has-error').length;
        if (errorNumber > 0) {
          return false;
        } else {
          return true;
        }
      };

      var _initProgramSteps = function () {
        const self = this;
        const form = $('#program-stream');
        return form.children('.program-steps').steps({
          headerTag: 'h4',
          bodyTag: 'section',
          transitionEffect: 'slideLeft',

          onStepChanging(event, currentIndex, newIndex) {
            if (currentIndex === 0 && newIndex === 1 && $('#description').is(':visible')) {
              form.valid();
              const name = $('#program_stream_name').val() === '';
              if (name) {
                return false;
              }
            } else if (currentIndex === 3 && newIndex === 4 && $('#trackings').is(':visible')) {
              if ($('#trackings').hasClass('hide-tracking-form')) {
                return true;
              }
              return _handleCheckingDuplicateFields() && _handleCheckTrackingName();
            } else if ($('#enrollment, #exit-program').is(':visible')) {
              return _handleCheckingDuplicateFields();
              if (_handleCheckingDuplicateFields()) {
                return false;
              }
            } else if ($('#rule-tab').is(':visible')) {
              if (_handleMaximumProgramEnrollment()) {
                return false;
              }
            }
            return $('section ul.frmb.ui-sortable').css('min-height', '266px');
          },

          onStepChanged(event, currentIndex, newIndex) {
            _stickyFill();
            const buttonSave = $('#btn-save-draft');
            if ($('#rule-tab').is(':visible')) {
              return _handleRemoveProgramList();
            } else if ($('#exit-program').is(':visible')) {
              return $(buttonSave).hide();
            } else {
              return $(buttonSave).show();
            }
          },

          onFinished(event, currentIndex) {
            $('.actions a:contains("Finish")').removeAttr('href');
            if (!_handleCheckingDuplicateFields()) {
              return false;
            }
            _handleRemoveUnuseInput();
            _handleAddRuleBuilderToInput();
            _handleSetValueToField();
            return form.submit();
          },

          labels: {
            finish: self.filterTranslation.save,
            next: self.filterTranslation.next,
            previous: self.filterTranslation.previous,
          },
        });
      };

      var _handleCheckTrackingName = function () {
        const nameFields = $('.program_stream_trackings_name:visible input[type="text"].error');
        if ($(nameFields).length > 0) {
          return false;
        } else {
          return true;
        }
      };

      var _handleClickAddTracking = function () {
        if ($('#trackings .frmb').length === 0) {
          return $('.links a').trigger('click');
        }
      };

      var _handleInitProgramFields = function () {
        for (var element of $('#enrollment, #exit-program')) {
          var dataElement = $(element).data('field');
          _initProgramBuilder($(element), dataElement || []);
          if (element.id === 'enrollment' && $('#program_stream_id').val() !== '') {
            _preventRemoveField(ENROLLMENT_URL, '#enrollment');
          } else if (element.id === 'exit-program' && $('#program_stream_id').val() !== '') {
            _preventRemoveField(EXIT_PROGRAM_URL, '#exit-program');
          }
        }

        const trackings = $('.tracking-builder');
        for (var tracking of trackings) {
          var trackingValue = $(tracking).data('tracking');
          _initProgramBuilder(tracking, trackingValue || []);
        }
        if ($('#program_stream_id').val() !== '') {
          return _preventRemoveField(TRACKING_URL, '');
        }
      };

      var _initButtonSave = function () {
        const form = $('form#program-stream');
        const btnSaveTranslation = filterTranslation.save;
        return form
          .find('[aria-label=Pagination]')
          .append(
            `<li><span id='btn-save-draft' class='btn btn-primary btn-sm'>${btnSaveTranslation}</span></li>`,
          );
      };

      var _handleRemoveUnuseInput = function () {
        const elements = $(
          '#program-rule ,#enrollment .form-wrap.form-builder, #tracking .form-wrap.form-builder, #exit-program .form-wrap.form-builder',
        );
        return $(elements).find('input, select, radio, checkbox, textarea').remove();
      };

      var _handleAddRuleBuilderToInput = function () {
        const rules = $('#program-rule').queryBuilder('getRules');
        if ($.isEmptyObject(rules)) {
          $('ul.rules-list li').removeClass('has-error');
        }
        if (!$.isEmptyObject(rules)) {
          return $('#program_stream_rules').val(_handleStringfyRules(rules));
        }
      };

      var _handleSetValueToField = function () {
        return (() => {
          const result = [];
          for (var formBuilder of this.formBuilder) {
            var { element } = formBuilder;
            if ($(element).is('#enrollment')) {
              result.push($('#program_stream_enrollment').val(formBuilder.formData));
            } else if ($(element).is('.tracking-builder')) {
              var hiddenField = $(element).find('.tracking-field-hidden input[type="hidden"]');
              result.push($(hiddenField).val(formBuilder.formData));
            } else if ($(element).is('#exit-program')) {
              result.push($('#program_stream_exit_program').val(formBuilder.formData));
            } else {
              result.push(undefined);
            }
          }
          return result;
        })();
      };

      var _handleStringfyRules = function (rules) {
        rules = JSON.stringify(rules);
        return rules.replace(/null/g, '""');
      };

      var _addFooterForSubmitForm = () => $('.actions.clearfix').addClass('ibox-footer');

      var _handleHideTracking = function () {
        if ($('#program_stream_tracking_required').prop('checked')) {
          $('#trackings').addClass('hide-tracking-form');
        }
        return $('#program_stream_tracking_required').on('ifChecked', () =>
          $('#trackings').addClass('hide-tracking-form'),
        );
      };

      var _handleShowTracking = () =>
        $('#program_stream_tracking_required').on('ifUnchecked', () =>
          $('#trackings').removeClass('hide-tracking-form'),
        );

      var _preventRemoveField = function (url, elementId) {
        if (this.programStreamId === '') {
          return false;
        }
        return $.ajax({
          method: 'GET',
          url,
          dataType: 'JSON',
          success(response) {
            if (response.field === 'tracking') {
              return _hideActionInTracking(response);
            } else {
              const fields = response.program_streams;
              const labelFields = $(elementId).find('label.field-label');
              return (() => {
                const result = [];
                for (var labelField of labelFields) {
                  var text = labelField.textContent;
                  if (fields.includes(text)) {
                    var parent = $(labelField).parent();
                    result.push($(parent).children('div.field-actions').remove());
                  } else {
                    result.push(undefined);
                  }
                }
                return result;
              })();
            }
          },
        });
      };

      var _hideActionInTracking = function (fields) {
        const trackings = $('#trackings .nested-fields');
        for (var tracking of trackings) {
          var trackingName = $(tracking).find('input.string.optional.readonly.form-control');
          if ($(trackingName).length === 0) {
            return;
          }
          var name = $(trackingName).val();
          var labelFields = $(tracking).find('label.field-label');
          for (var labelField of labelFields) {
            var parent = $(labelField).parent();
            for (var field of fields[name]) {
              if (labelField.textContent === field) {
                $(parent).children('div.field-actions').remove();
                $(tracking).find('.ibox-footer').remove();
              }
            }
          }
        }
      };

      var _initFrequencyNote = () =>
        (() => {
          const result = [];
          for (var nestedField of $('.nested-fields')) {
            var select = $(nestedField).find('.program_stream_trackings_frequency select');
            var timeFrequency = $(nestedField).find(
              '.program_stream_trackings_time_of_frequency input',
            );
            var elementNote = $(nestedField).find('.frequency-note');
            var frequency = _convertFrequency($(select).val());
            var value = parseInt(timeFrequency.val());
            if (frequency === '') {
              $(timeFrequency).attr({ readonly: true });
            }
            if (value > 0) {
              _updateFrequencyNote(value, frequency, elementNote);
            }
            result.push(_timeOfFrequencyChange(timeFrequency, frequency, elementNote));
          }
          return result;
        })();

      var _handleRemoveFrequency = function () {
        const frequencies = $('.program_stream_trackings_frequency select');
        return $(frequencies).on('select2-removed', function (element) {
          const select = element.currentTarget;
          const nestedField = $(select).parents('.nested-fields');
          const timeOfFrequency = $(nestedField).find(
            '.program_stream_trackings_time_of_frequency input',
          );
          $(nestedField).find('.frequency-note i').text('');
          $(timeOfFrequency).val(0);
          return $(timeOfFrequency).attr({ readonly: true });
        });
      };

      var _handleSelectFrequency = function () {
        const frequencies = $('.program_stream_trackings_frequency select');
        return $(frequencies).on('select2-selecting', function (element) {
          const select = element.currentTarget;
          const frequencyNote = select.parentElement.nextElementSibling;
          const frequencyValue = _convertFrequency(element.val);

          const nested = $(select).parents('.nested-fields');
          const timeOfFrequency = $(nested).find(
            '.program_stream_trackings_time_of_frequency input',
          );
          $(timeOfFrequency).removeAttr('readonly');
          if ($(timeOfFrequency).val() <= 0) {
            $(timeOfFrequency).val(1);
          }
          const value = parseInt($(timeOfFrequency).val());
          _updateFrequencyNote(value, frequencyValue, frequencyNote);
          return _timeOfFrequencyChange(timeOfFrequency, frequencyValue, frequencyNote);
        });
      };

      var _timeOfFrequencyChange = (timeOfFrequency, frequencyValue, frequencyNote) =>
        $(timeOfFrequency).on('change', function () {
          const value = parseInt($(this).val());
          if (value < 0) {
            $(this).val(0);
          }
          return _updateFrequencyNote(value, frequencyValue, frequencyNote);
        });

      var _updateFrequencyNote = function (value, frequency, element) {
        const frequencyNote = 'This needs to be done once every';
        const single = `${frequencyNote} ${frequency}`;
        const plural = `${frequencyNote} ${value} ${frequency}s`;
        const frequencNoteUpdate = (() => {
          if (value === 1) {
            return single;
          } else if (value > 1) {
            return plural;
          }
        })();
        $(element).find('i').text('');
        if (value > 0) {
          return $(element).find('i').text(frequencNoteUpdate);
        }
      };

      var _convertFrequency = function (frequency) {
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

      var _handleMaximumProgramEnrollment = function () {
        const quantity = $('#program_stream_quantity');
        if ($(quantity).val() < $(quantity).data('maximun') && $(quantity).val() !== '') {
          $('.help-block.quantity').removeClass('hidden');
          return true;
        } else {
          $('.help-block.quantity').addClass('hidden');
          return false;
        }
      };

      return { init: _init };
    })();
