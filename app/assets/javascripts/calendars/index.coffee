CIF.CalendarsIndex = do ->
  _init = ->
    _calendars()
    _bindTaskModal()

  # fullCalendar event FEED (function form, not a static array) so a task created via the modal can be
  # reflected immediately with refetchEvents(). Root-relative URL (leading slash) + .done/.fail (the app's
  # jQuery is 1.x today, but this stays correct if it is ever upgraded past the removed .success/.error).
  _eventsFeed = (start, end, timezone, callback) ->
    $.ajax(
      type: 'GET'
      url: '/api/calendars/find_event'
      dataType: 'JSON'
    ).done((json) ->
      callback(_fillFullCalendarArray((json && json.calendars) || []))
      $('.loader').hide()
    ).fail(->
      # Never leave the spinner hanging if the feed fails; the (empty) calendar still renders.
      $('.loader').hide()
    )

  _calendars = ->
    $('#calendar').fullCalendar(
      header:
        left: 'prev,next today'
        center: 'title'
        right: 'agendaDay,agendaWeek,month,agendaFourDay'
      views:
        agendaFourDay:
          type: 'agenda'
          duration: { days: 4 }
          buttonText: '4 days'
      events: _eventsFeed
      dayClick: (date, jsEvent, view) ->
        _openTaskModal(date)
      eventRender: (event, element) ->
        element.popover
          animation: true
          delay: 200
          placement: 'top'
          content: event.title
          trigger: 'hover'
          container: 'body'
    )

  _fillFullCalendarArray = (eventLists) ->
    events = []
    for eventList in eventLists
      summary = eventList.title
      startDate = eventList.start_date
      endDate = eventList.end_date
      fullDate = null
      if (Date.parse(startDate) + 86400000) == Date.parse(endDate)
        fullDate = true
      events.push(
        title: summary
        start: moment.parseZone(startDate)
        end: moment.parseZone(endDate)
        allDay: fullDate
      )
    events

  # ---- Date-click task modal -------------------------------------------------

  _resetClientSelect = (placeholderKey) ->
    select = $('#task-client')
    return unless select.length
    text = select.data(placeholderKey) || ''
    select.html('<option value="">' + _escape(text) + '</option>')

  _openTaskModal = (date) ->
    modal = $('#taskModal')
    return unless modal.length
    $('#task-program').val('')
    $('#task-domain').val('')
    $('#task-name').val('')
    $('#task-remind-at').val('')
    $('#task-client').prop('disabled', true)
    _resetClientSelect('placeholder-empty')
    $('#task-completion-date').val(if date && date.format then date.format('YYYY-MM-DD') else '')
    _hideTaskError()
    modal.modal('show')

  _loadProgramClients = ->
    select = $('#task-client')
    programId = $('#task-program').val()
    unless programId
      select.prop('disabled', true)
      _resetClientSelect('placeholder-empty')
      return
    select.prop('disabled', true)
    _resetClientSelect('placeholder-loading')
    $.ajax(
      type: 'GET'
      url: '/api/calendars/program_clients'
      data: { program_id: programId }
      dataType: 'JSON'
    ).done((clients) ->
      list = clients || []
      if list.length == 0
        select.prop('disabled', true)
        _resetClientSelect('placeholder-none')
        return
      opts = ['<option value="">' + _escape(select.data('placeholder-select')) + '</option>']
      for client in list
        opts.push('<option value="' + _escape(String(client.id)) + '">' + _escape(client.name) + '</option>')
      select.html(opts.join('')).prop('disabled', false)
    ).fail(->
      select.prop('disabled', true)
      _resetClientSelect('placeholder-error')
    )

  _submitTask = (e) ->
    e.preventDefault()
    clientId = $('#task-client').val()
    domainId = $('#task-domain').val()
    name = $.trim($('#task-name').val())
    completionDate = $('#task-completion-date').val()
    remindAt = $('#task-remind-at').val()
    form = $('#new-task-form')
    unless clientId && domainId && name && completionDate
      _showTaskError(form.data('error-required'))
      return
    submit = $('#task-submit')
    submit.prop('disabled', true).text(submit.data('label-creating'))
    _hideTaskError()
    $.ajax(
      type: 'POST'
      url: '/clients/' + encodeURIComponent(clientId) + '/tasks'
      dataType: 'JSON'
      headers: { 'X-CSRF-Token': $('meta[name="csrf-token"]').attr('content') }
      data: { task: { domain_id: domainId, name: name, completion_date: completionDate, remind_at: remindAt } }
    ).done(->
      $('#taskModal').modal('hide')
      $('#calendar').fullCalendar('refetchEvents')
    ).fail(->
      _showTaskError(form.data('error-save'))
    ).always(->
      submit.prop('disabled', false).text(submit.data('label-create'))
    )

  _bindTaskModal = ->
    return unless $('#taskModal').length
    $('#task-program').on('change', _loadProgramClients)
    $('#new-task-form').on('submit', _submitTask)

  # ---- helpers ---------------------------------------------------------------

  _escape = (value) ->
    String(if value? then value else '')
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;')

  _showTaskError = (msg) ->
    $('.task-modal-error').text(msg || '').removeClass('hidden')

  _hideTaskError = ->
    $('.task-modal-error').addClass('hidden').text('')

  { init: _init }
