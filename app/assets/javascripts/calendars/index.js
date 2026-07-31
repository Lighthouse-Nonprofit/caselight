CIF.CalendarsIndex = (function () {
  // POAM-017d: FullCalendar 6 (vendored standard bundle, jQuery/moment-free).
  // Data-task batch (2026-07): the feed is TASK-NATIVE and FC6-ready — the server emits
  // explicit allDay + offset-less LOCAL wall times for the requested visible range, so the
  // old 24h-allDay heuristic and the offset-stripping shim are gone. timeGrid views are
  // first-class now (slot config below); week is the planning default.
  let calendar = null;

  const _init = function () {
    _calendars();
    return _bindTaskModal();
  };

  // FC6 events-as-function: pass the visible range through; the server scopes to it.
  // On failure render an empty calendar and never leave the spinner hanging.
  const _eventsFeed = (fetchInfo, success, failure) =>
    $.ajax({
      type: 'GET',
      url: '/api/calendars/find_event',
      dataType: 'JSON',
      data: { start: fetchInfo.startStr, end: fetchInfo.endStr },
    })
      .done(function (events) {
        success(events || []);
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
        right: 'timeGridDay,timeGridWeek,dayGridMonth,timeGridFourDay',
      },
      views: {
        timeGridFourDay: {
          type: 'timeGrid',
          duration: { days: 4 },
          buttonText: '4 days',
        },
      },
      initialView: 'timeGridWeek',
      nowIndicator: true,
      scrollTime: '08:00:00',
      slotDuration: '00:30:00',
      slotMinTime: '06:00:00',
      slotMaxTime: '20:00:00',
      businessHours: { daysOfWeek: [1, 2, 3, 4, 5], startTime: '08:00', endTime: '17:00' },
      height: 'auto',
      events: _eventsFeed,
      // Drag/drop + resize reschedule. durationEditable comes per-event from the feed
      // (timed tasks only), so all-day events can move but not stretch.
      editable: true,
      eventDrop(info) {
        return _reschedule(info);
      },
      eventResize(info) {
        return _reschedule(info);
      },
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

  // ---- Drag/drop reschedule ----------------------------------------------------

  // PATCH the new slot to the server; revert the pixels if it refuses. A drop into the
  // all-day lane sends a blank start_time (jQuery serializes null as ""), which the server
  // treats as "clear the time AND the duration". Success refetches so the overdue/today/
  // upcoming bucket colors follow the event to its new date.
  const _reschedule = function (info) {
    const event = info.event;
    const payload = {
      completion_date: event.startStr.slice(0, 10),
      start_time: event.allDay ? null : event.startStr.slice(11, 16),
      duration_minutes:
        !event.allDay && event.end ? Math.round((event.end - event.start) / 60000) : null,
    };
    return $.ajax({
      type: 'PATCH',
      url: '/tasks/' + encodeURIComponent(event.id) + '/reschedule',
      // head :ok has an empty body — asking jQuery for JSON would parse-fail and revert good saves
      dataType: 'text',
      headers: { 'X-CSRF-Token': $('meta[name="csrf-token"]').attr('content') },
      data: { task: payload },
    })
      .done(() => calendar && calendar.refetchEvents())
      .fail(function () {
        return info.revert();
      });
  };

  // ---- Date-click task modal -------------------------------------------------

  // Owner flip (2026-07-31): Person first, then Program — the program select is the
  // dependent one now.
  const _resetProgramSelect = function (placeholderKey) {
    const select = $('#task-program');
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
    $('#task-client').val('');
    $('#task-domain').val('');
    $('#task-name').val('');
    $('#task-program').prop('disabled', true);
    _resetProgramSelect('placeholder-empty');
    // FC6 dateClick info.dateStr is ISO (date-only in dayGrid, datetime in timeGrid) —
    // first 10 chars = the YYYY-MM-DD the old moment .format() produced
    $('#task-completion-date').val(info && info.dateStr ? info.dateStr.slice(0, 10) : '');
    // timeGrid clicks carry a time — prefill the slot the case manager clicked
    const clickedTime = info && info.dateStr && info.dateStr.length > 10 ? info.dateStr.slice(11, 16) : '';
    $('#task-start-time').val(clickedTime);
    $('#task-duration').val(clickedTime ? '60' : '');
    _hideTaskError();
    return bootstrap.Modal.getOrCreateInstance(modal[0]).show();
  };

  const _loadClientPrograms = function () {
    const select = $('#task-program');
    const clientId = $('#task-client').val();
    if (!clientId) {
      select.prop('disabled', true);
      _resetProgramSelect('placeholder-empty');
      return;
    }
    select.prop('disabled', true);
    _resetProgramSelect('placeholder-loading');
    return $.ajax({
      type: 'GET',
      url: '/api/calendars/client_programs',
      data: { client_id: clientId },
      dataType: 'JSON',
    })
      .done(function (programs) {
        const list = programs || [];
        if (list.length === 0) {
          select.prop('disabled', true);
          _resetProgramSelect('placeholder-none');
          return;
        }
        const opts = [
          '<option value="">' + _escape(select.data('placeholder-select')) + '</option>',
        ];
        for (var program of list) {
          opts.push(
            '<option value="' +
              _escape(String(program.id)) +
              '">' +
              _escape(program.name) +
              '</option>',
          );
        }
        select.html(opts.join('')).prop('disabled', false);
        // one active program: pre-select it — the common pilot case
        if (list.length === 1) {
          select.val(String(list[0].id));
        }
        return select;
      })
      .fail(function () {
        select.prop('disabled', true);
        return _resetProgramSelect('placeholder-error');
      });
  };

  const _submitTask = function (e) {
    e.preventDefault();
    const clientId = $('#task-client').val();
    const domainId = $('#task-domain').val();
    const name = ($('#task-name').val() || '').trim(); // $.trim removed in jQuery 4
    const completionDate = $('#task-completion-date').val();
    const startTime = $('#task-start-time').val();
    const duration = $('#task-duration').val();
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
        task: {
          domain_id: domainId,
          name,
          completion_date: completionDate,
          start_time: startTime || null,
          duration_minutes: startTime && duration ? duration : null,
        },
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
    $('#task-client').on('change', _loadClientPrograms);
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
