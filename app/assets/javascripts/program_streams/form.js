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
      let programRuleBuilder;
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
        // POAM-017g flip: iCheck removed — checkboxes are native .form-check-input (no init).
      };

      const _stickyFill = function () {
        if ($('.form-wrap').is(':visible')) {
          return $('.cb-wrap').Stickyfill();
        }
      };

      var _initSelect2 = () => CIF.Select.init('#description select, #rule-tab select');

      var _initSelect2TimeOfFrequency = () =>
        CIF.Select.init('.program_stream_trackings_frequency select', { allowClear: true });

      const _handleRemoveProgramList = function () {
        const programExclusive = $('#program_stream_program_exclusive');
        const mutualDependence = $('#program_stream_mutual_dependence');
        _selectOptonProgramExclusive(programExclusive, mutualDependence);
        return _selectOptonMutualDependence(programExclusive, mutualDependence);
      };

      // NB (POAM-017c): these two selects flip option `disabled` flags on EACH OTHER.
      // select2 v3 read the native options live on every open; Tom Select caches them,
      // so every native toggle is followed by a selection-preserving resyncOptions.
      var _selectOptonProgramExclusive = function (programExclusive, mutualDependence) {
        if ($(programExclusive).val() !== null) {
          for (var value of $(programExclusive).val()) {
            $(mutualDependence).find(`option[value=${value}]`).attr('disabled', true);
          }
          CIF.Select.resyncOptions(mutualDependence);
        }

        CIF.Select.on(programExclusive, 'item_add', function (value) {
          $(mutualDependence).find(`option[value=${value}]`).attr('disabled', true);
          return CIF.Select.resyncOptions(mutualDependence);
        });

        return CIF.Select.on(programExclusive, 'item_remove', function (value) {
          $(mutualDependence).find(`option[value=${value}]`).removeAttr('disabled');
          return CIF.Select.resyncOptions(mutualDependence);
        });
      };

      var _selectOptonMutualDependence = function (programExclusive, mutualDependence) {
        if ($(mutualDependence).val() !== null) {
          for (var value of mutualDependence.val()) {
            $(programExclusive).find(`option[value=${value}]`).attr('disabled', true);
          }
          CIF.Select.resyncOptions(programExclusive);
        }

        CIF.Select.on(mutualDependence, 'item_add', function (value) {
          $(programExclusive).find(`option[value=${value}]`).attr('disabled', true);
          return CIF.Select.resyncOptions(programExclusive);
        });

        return CIF.Select.on(mutualDependence, 'item_remove', function (value) {
          $(programExclusive).find(`option[value=${value}]`).removeAttr('disabled');
          return CIF.Select.resyncOptions(programExclusive);
        });
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
        // empty on /new — this JSON.parse('') throw was previously masked by the
        // ConfigError that killed the init before reaching here (POAM-017f defect)
        const raw = $('#program_stream_rules').val();
        if (!raw) {
          return;
        }
        const rules = JSON.parse(raw.replace(/=>/g, ':'));
        if (!$.isEmptyObject(rules)) {
          return programRuleBuilder.setRules(rules);
        }
      };

      var _addRuleCallback = () =>
        $('#program-rule').on('rulebuilder:rule-rendered', function () {
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
        // re-init the operator/value selects the queryBuilder swaps in after a rule change
        // (CIF.Select.init is idempotent, so already-live widgets are untouched)
        CIF.Select.on('select', 'item_add', () =>
          setTimeout(
            () =>
              CIF.Select.init('.rule-operator-container select, .rule-value-container select', {
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
            // the API renders the RuleFields array BARE — the old
            // response.program_stream_add_rule read was undefined, which is what threw
            // queryBuilder's "ConfigError: Missing filters list" on /program_streams/new
            // (POAM-017f latent defect)
            const fieldList = response;
            programRuleBuilder = new CIF.RuleBuilder($('#program-rule')[0], {
              filters: fieldList,
              lang: {
                add_rule: filterTranslation.addFilter,
                add_group: filterTranslation.addGroup,
                delete_group: filterTranslation.deleteGroup,
              },
            });
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
        // formBuilder 3.x returns the instance (no .data('formBuilder')) and no longer
        // exposes .element -- track the {instance, element} pair for _handleSetValueToField;
        // shared options from CIF.CustomFormBuilder#builderOptions
        const instance = $(element).formBuilder(builderOption.builderOptions({ formData: data }));
        this.formBuilder.push({ instance, element });
        return instance;
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
        // formBuilder 3.x init is ASYNC — _preventRemoveField walks the rendered stage,
        // so each call rides its builder's instance promise
        for (var element of $('#enrollment, #exit-program')) {
          var dataElement = $(element).data('field');
          var instance = _initProgramBuilder($(element), dataElement || []);
          if (element.id === 'enrollment' && $('#program_stream_id').val() !== '') {
            instance.promise.then(() => _preventRemoveField(ENROLLMENT_URL, '#enrollment'));
          } else if (element.id === 'exit-program' && $('#program_stream_id').val() !== '') {
            instance.promise.then(() => _preventRemoveField(EXIT_PROGRAM_URL, '#exit-program'));
          }
        }

        const trackings = $('.tracking-builder');
        let lastTracking;
        for (var tracking of trackings) {
          var trackingValue = $(tracking).data('tracking');
          lastTracking = _initProgramBuilder(tracking, trackingValue || []);
        }
        if ($('#program_stream_id').val() !== '') {
          if (lastTracking) {
            return lastTracking.promise.then(() => _preventRemoveField(TRACKING_URL, ''));
          }
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
        if (!programRuleBuilder) {
          return;
        }
        // null when empty/invalid -> hidden field untouched and the error paint stays,
        // exactly the legacy behavior (the old error-clearing line here targeted
        // 'ul.rules-list li', a selector that never matched QB 2.5's div markup)
        const rules = programRuleBuilder.getRules();
        if (!$.isEmptyObject(rules)) {
          return $('#program_stream_rules').val(_handleStringfyRules(rules));
        }
      };

      var _handleSetValueToField = function () {
        return (() => {
          const result = [];
          // entries are {instance, element} pairs — 3.x instances no longer carry .element
          for (var entry of this.formBuilder) {
            var { element } = entry;
            if ($(element).is('#enrollment')) {
              result.push($('#program_stream_enrollment').val(entry.instance.formData));
            } else if ($(element).is('.tracking-builder')) {
              var hiddenField = $(element).find('.tracking-field-hidden input[type="hidden"]');
              result.push($(hiddenField).val(entry.instance.formData));
            } else if ($(element).is('#exit-program')) {
              result.push($('#program_stream_exit_program').val(entry.instance.formData));
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
        return CIF.Select.on(frequencies, 'item_remove', function (value, select) {
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
        return CIF.Select.on(frequencies, 'item_add', function (selectedValue, select) {
          const frequencyNote = select.parentElement.nextElementSibling;
          const frequencyValue = _convertFrequency(selectedValue);

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
          $('.form-text.quantity').removeClass('hidden');
          return true;
        } else {
          $('.form-text.quantity').addClass('hidden');
          return false;
        }
      };

      return { init: _init };
    })();
