CIF.CalendarsIndex = (function () {
  // POAM-017d: FullCalendar 6 (vendored standard bundle, jQuery/moment-free) replaced the
  // fullcalendar-rails 3.9 + momentjs-rails gems. Module-level instance so the task modal
  // can refetchEvents() after a create. The /api/calendars/find_event FEED CONTRACT and the
  // all-day heuristic are deliberately unchanged.
  let calendar = null;

  const _init = function () {
    _calendars();
    return _bindTaskModal();
  };

  // FC6 events-as-function: (fetchInfo, success, failure). The feed still returns the whole
  // set (it never used the visible range). On failure render an empty calendar and never
  // leave the spinner hanging — same behavior as before.
  const _eventsFeed = (fetchInfo, success, failure) =>
    $.ajax({
      type: 'GET',
      url: '/api/calendars/find_event',
      dataType: 'JSON',
    })
      .done(function (json) {
        success(_fillFullCalendarArray((json && json.calendars) || []));
        return $('.loader').hide();
      })
      .fail(function () {
        success([]);
        return $('.loader').hide();
      });

  var _calendars = function () {
    const el = document.getElementById('calendar');
    if (!el) {
      return;
    }
    calendar = new FullCalendar.Calendar(el, {
      headerToolbar: {
        left: 'prev,next today',
        center: 'title',
        // FC3 agendaDay/agendaWeek/month -> FC6 timeGrid/dayGrid names
        right: 'timeGridDay,timeGridWeek,dayGridMonth,timeGridFourDay',
      },
      views: {
        timeGridFourDay: {
          type: 'timeGrid',
          duration: { days: 4 },
          buttonText: '4 days',
        },
      },
      events: _eventsFeed,
      dateClick(info) {
        return _openTaskModal(info);
      },
      eventDidMount(info) {
        return new bootstrap.Popover(info.el, {
          animation: true,
          delay: 200,
          placement: 'top',
          content: info.event.title,
          trigger: 'hover',
          container: 'body',
        });
      },
    });
    return calendar.render();
  };

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
        // moment.parseZone displayed the timestamp's OWN wall clock; FC6's default 'local'
        // timezone would shift Z-suffixed feed times into the browser zone (a task dated
        // the 15th at 00:00Z rendered on the evening of the 14th — caught in QA). Strip
        // the offset so FC6 renders the feed's wall time as-is, matching the old widget.
        start: _wallTime(startDate),
        end: _wallTime(endDate),
        allDay: fullDate,
      });
    }
    return events;
  };

  var _wallTime = (value) =>
    String(value != null ? value : '').replace(/(\.\d+)?(Z|[+-]\d{2}:?\d{2})$/, '');

  // ---- Date-click task modal -------------------------------------------------

  const _resetClientSelect = function (placeholderKey) {
    const select = $('#task-client');
    if (!select.length) {
      return;
    }
    const text = select.data(placeholderKey) || '';
    return select.html('<option value="">' + _escape(text) + '</option>');
  };

  var _openTaskModal = function (info) {
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
    // FC6 dateClick info.dateStr is ISO (date-only in dayGrid, datetime in timeGrid) —
    // first 10 chars = the YYYY-MM-DD the old moment .format() produced
    $('#task-completion-date').val(info && info.dateStr ? info.dateStr.slice(0, 10) : '');
    _hideTaskError();
    return bootstrap.Modal.getOrCreateInstance(modal[0]).show();
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
    const name = ($('#task-name').val() || '').trim(); // $.trim removed in jQuery 4
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
        var taskModalEl = document.getElementById('taskModal');
        if (taskModalEl) { bootstrap.Modal.getOrCreateInstance(taskModalEl).hide(); }
        return calendar && calendar.refetchEvents();
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
      .removeClass('hidden d-none');

  var _hideTaskError = () => $('.task-modal-error').addClass('hidden').text('');

  return { init: _init };
})();
