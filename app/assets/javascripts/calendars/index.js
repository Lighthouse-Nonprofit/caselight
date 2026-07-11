CIF.CalendarsIndex = (function () {
  const _init = function () {
    _calendars();
    return _bindTaskModal();
  };

  // fullCalendar event FEED (function form, not a static array) so a task created via the modal can be
  // reflected immediately with refetchEvents(). Root-relative URL (leading slash) + .done/.fail (the app's
  // jQuery is 1.x today, but this stays correct if it is ever upgraded past the removed .success/.error).
  const _eventsFeed = (start, end, timezone, callback) =>
    $.ajax({
      type: 'GET',
      url: '/api/calendars/find_event',
      dataType: 'JSON',
    })
      .done(function (json) {
        callback(_fillFullCalendarArray((json && json.calendars) || []));
        return $('.loader').hide();
      })
      .fail(() =>
        // Never leave the spinner hanging if the feed fails; the (empty) calendar still renders.
        $('.loader').hide(),
      );

  var _calendars = () =>
    $('#calendar').fullCalendar({
      header: {
        left: 'prev,next today',
        center: 'title',
        right: 'agendaDay,agendaWeek,month,agendaFourDay',
      },
      views: {
        agendaFourDay: {
          type: 'agenda',
          duration: { days: 4 },
          buttonText: '4 days',
        },
      },
      events: _eventsFeed,
      dayClick(date, jsEvent, view) {
        return _openTaskModal(date);
      },
      eventRender(event, element) {
        return element.popover({
          animation: true,
          delay: 200,
          placement: 'top',
          content: event.title,
          trigger: 'hover',
          container: 'body',
        });
      },
    });

  var _fillFullCalendarArray = function (eventLists) {
    const events = [];
    for (var eventList of eventLists) {
      var summary = eventList.title;
      var startDate = eventList.start_date;
      var endDate = eventList.end_date;
      var fullDate = null;
      if (Date.parse(startDate) + 86400000 === Date.parse(endDate)) {
        fullDate = true;
      }
      events.push({
        title: summary,
        start: moment.parseZone(startDate),
        end: moment.parseZone(endDate),
        allDay: fullDate,
      });
    }
    return events;
  };

  // ---- Date-click task modal -------------------------------------------------

  const _resetClientSelect = function (placeholderKey) {
    const select = $('#task-client');
    if (!select.length) {
      return;
    }
    const text = select.data(placeholderKey) || '';
    return select.html('<option value="">' + _escape(text) + '</option>');
  };

  var _openTaskModal = function (date) {
    const modal = $('#taskModal');
    if (!modal.length) {
      return;
    }
    $('#task-program').val('');
    $('#task-domain').val('');
    $('#task-name').val('');
    $('#task-remind-at').val('');
    $('#task-client').prop('disabled', true);
    _resetClientSelect('placeholder-empty');
    $('#task-completion-date').val(date && date.format ? date.format('YYYY-MM-DD') : '');
    _hideTaskError();
    return modal.modal('show');
  };

  const _loadProgramClients = function () {
    const select = $('#task-client');
    const programId = $('#task-program').val();
    if (!programId) {
      select.prop('disabled', true);
      _resetClientSelect('placeholder-empty');
      return;
    }
    select.prop('disabled', true);
    _resetClientSelect('placeholder-loading');
    return $.ajax({
      type: 'GET',
      url: '/api/calendars/program_clients',
      data: { program_id: programId },
      dataType: 'JSON',
    })
      .done(function (clients) {
        const list = clients || [];
        if (list.length === 0) {
          select.prop('disabled', true);
          _resetClientSelect('placeholder-none');
          return;
        }
        const opts = [
          '<option value="">' + _escape(select.data('placeholder-select')) + '</option>',
        ];
        for (var client of list) {
          opts.push(
            '<option value="' +
              _escape(String(client.id)) +
              '">' +
              _escape(client.name) +
              '</option>',
          );
        }
        return select.html(opts.join('')).prop('disabled', false);
      })
      .fail(function () {
        select.prop('disabled', true);
        return _resetClientSelect('placeholder-error');
      });
  };

  const _submitTask = function (e) {
    e.preventDefault();
    const clientId = $('#task-client').val();
    const domainId = $('#task-domain').val();
    const name = $.trim($('#task-name').val());
    const completionDate = $('#task-completion-date').val();
    const remindAt = $('#task-remind-at').val();
    const form = $('#new-task-form');
    if (!clientId || !domainId || !name || !completionDate) {
      _showTaskError(form.data('error-required'));
      return;
    }
    const submit = $('#task-submit');
    submit.prop('disabled', true).text(submit.data('label-creating'));
    _hideTaskError();
    return $.ajax({
      type: 'POST',
      url: '/clients/' + encodeURIComponent(clientId) + '/tasks',
      dataType: 'JSON',
      headers: { 'X-CSRF-Token': $('meta[name="csrf-token"]').attr('content') },
      data: {
        task: { domain_id: domainId, name, completion_date: completionDate, remind_at: remindAt },
      },
    })
      .done(function () {
        $('#taskModal').modal('hide');
        return $('#calendar').fullCalendar('refetchEvents');
      })
      .fail(() => _showTaskError(form.data('error-save')))
      .always(() => submit.prop('disabled', false).text(submit.data('label-create')));
  };

  var _bindTaskModal = function () {
    if (!$('#taskModal').length) {
      return;
    }
    $('#task-program').on('change', _loadProgramClients);
    return $('#new-task-form').on('submit', _submitTask);
  };

  // ---- helpers ---------------------------------------------------------------

  var _escape = (value) =>
    String(value != null ? value : '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');

  var _showTaskError = (msg) =>
    $('.task-modal-error')
      .text(msg || '')
      .removeClass('hidden');

  var _hideTaskError = () => $('.task-modal-error').addClass('hidden').text('');

  return { init: _init };
})();
