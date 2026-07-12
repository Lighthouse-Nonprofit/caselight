CIF.Progress_notesNew =
  CIF.Progress_notesCreate =
  CIF.Progress_notesEdit =
  CIF.Progress_notesUpdate =
    (function () {
      // jQuery-3 fix (POAM-017b): must run at script PARSE time, not inside _init. jQuery 3's
      // ready callback fires asynchronously AFTER native DOMContentLoaded listeners, so Dropzone's
      // own auto-discover attached to form.dropzone first and the manual attach in _initDropzone
      // then threw "Dropzone already attached". (On jQuery 1.x the ready handler happened to win
      // the race, masking the latent double-init.)
      Dropzone.autoDiscover = false;

      const _init = function () {
        self.removeFile = [];
        _handleEnableSubmitButtonWhenRemoveFile();
        _initDropzone();
        _select2();
        _toggleOtherLocation();
        _triggerLocationChanged();
        return _handleSubmitForm();
      };
      // POAM-017a: TinyMCE init removed — the Trix editors (<trix-editor> in the form
      // partial) bind themselves; app-wide Trix config lives in rich_text.js.

      var _handleSubmitForm = function () {
        const self = this;
        return $('#only-submit').on('click', function () {
          _handleRemoveImageFileById();
          return $('form.progress-note input[type=submit]').click();
        });
      };

      const _handleCollectingRemoveFileId = () =>
        $('.dz-remove').on('click', function () {
          const file_id = $(this).closest('.dz-preview').data('id');
          return self.removeFile.push(file_id);
        });

      var _handleRemoveImageFileById = function () {
        if (self.removeFile !== undefined) {
          const id = $('#progress_note_id').val();
          return $.ajax({
            type: 'GET',
            url: '/attachments/delete',
            data: { attachments: self.removeFile, progress_note_id: id },
            dataType: 'JSON',
          }).done(
            (json) =>
              // jQuery-3 prep: jqXHR.success was removed in 3.0
              false,
          );
        }
      };

      var _select2 = () => CIF.Select.init('select', { allowClear: true });

      var _toggleOtherLocation = function () {
        const selectedOption = $('.progress_note_location select option:selected');
        if (selectedOption.text().toLowerCase().indexOf('other') >= 0) {
          return $('input#progress_note_other_location').removeAttr('disabled');
        } else {
          return $('input#progress_note_other_location').attr('disabled', 'disabled').val('');
        }
      };

      var _triggerLocationChanged = () =>
        $('.progress_note_location select').change(() => _toggleOtherLocation());

      const _clearProgressNoteDateError = function () {
        $('.form-text').remove();
        return $('.has-error').removeClass('has-error');
      };

      const _addProgressNoteDateError = function () {
        $('#progress_note_date').removeClass('has-error');
        $('.form-text').remove();
        const errorText = $('#progress_note_error_text').val();
        $('#progress_note_date').addClass('has-error');
        return $('#progress_note_date')
          .closest('.mb-3')
          .append(`<span class='form-text' style='display:block;'> ${errorText} </span>`);
      };

      var _handleEnableSubmitButtonWhenRemoveFile = () =>
        $('.dz-remove').on('click', function () {
          if ($('.dz-error-message span').text() !== '') {
            return $('#only-submit').attr('disabled', 'disabled');
          } else {
            return $('#only-submit').removeAttr('disabled');
          }
        });

      var _initDropzone = function () {
        let successCallBackCount = 1;
        const form = $('.dropzone');
        return form.dropzone({
          autoProcessQueue: false,
          acceptedFiles: '.jpeg,.jpg,.png,.pdf,.doc,.docx,.xls,.xlsx',
          paramName: 'attachments[file][]',
          maxFilesize: 5,
          addRemoveLinks: true,
          uploadMultiple: true,
          parallelUploads: 25,
          init() {
            let data;
            const myDropzone = this;
            let progressNoteId = $('#progress_note_id').val();
            if (typeof progressNoteId !== 'undefined') {
              data = { progress_note_id: progressNoteId };
              $.ajax({
                type: 'GET',
                url: '/attachments/',
                data,
                dataType: 'JSON',
              }).done(function (json) {
                // jQuery-3 prep: jqXHR.success was removed in 3.0
                const { attachments } = json;
                for (var attachment of attachments) {
                  var mockFile = {
                    name: attachment.name,
                    size: attachment.size,
                    url: attachment.file.file.url,
                    status: Dropzone.ADDED,
                  };

                  myDropzone.options.addedfile.call(myDropzone, mockFile);
                  myDropzone.files.push(mockFile);
                  $('.dz-preview:last-child').attr('data-id', attachment.id);
                }

                return _handleCollectingRemoveFileId();
              });
            }
            this.element
              .querySelector('form.progress-note input[type=submit]')
              .addEventListener('click', function (e) {
                $('.loader').removeClass('hide');
                $('form, .dummy-footer').addClass('hide');
                e.preventDefault();
                e.stopPropagation();
                if ($('#progress_note_date').val() !== '') {
                  _clearProgressNoteDateError();
                  progressNoteId = $('#progress_note_id').val();
                  if (typeof progressNoteId !== 'undefined' && myDropzone.files.length >= 1) {
                    return myDropzone.uploadFiles(myDropzone.files);
                  } else if (myDropzone.getQueuedFiles().length > 0) {
                    return myDropzone.processQueue();
                  } else {
                    return form.submit();
                  }
                } else {
                  _addProgressNoteDateError();
                  $('form, .dummy-footer').removeClass('hide');
                  return $('.loader').addClass('hide');
                }
              });
            this.on('addedfile', (file) => _handleEnableSubmitButtonWhenRemoveFile());
            this.on('success', function (file, response) {
              successCallBackCount += 1;
              const { text } = response;
              const slugId = response.slug_id;
              const progressNote = response.progress_note;
              if (text !== '' && successCallBackCount === this.files.length) {
                $('.loader').addClass('hide');
                $('form, .dummy-footer').removeClass('hide');
                $('#wrapper').data({
                  message: text,
                  messageType: 'notice',
                });
                CIF.Common.initNotification();
              }
              return setTimeout(
                () =>
                  (window.location.href = `/clients/${slugId}/progress_notes/${progressNote.id}`),
                1000,
              );
            });
            return this.on('error', function (file, response) {
              $('.loader').addClass('hide');
              $('form, .dummy-footer').removeClass('hide');
              if (file.size > 5242880) {
                return $('#only-submit').attr('disabled', 'disabled');
              } else {
                return $('#only-submit').removeAttr('disabled');
              }
            });
          },
        });
      };

      return { init: _init };
    })();
