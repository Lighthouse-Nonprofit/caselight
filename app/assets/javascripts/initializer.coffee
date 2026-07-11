CIF.Initializer =
  exec: (pageName) ->
    if pageName && CIF[pageName]
      CIF[pageName]['init']()

  currentPage: ->
    return '' unless $('body').attr('id')

    bodyId      = $('body').attr('id').split('-')
    action      = CIF.Util.capitalize(bodyId[1])
    controller  = CIF.Util.capitalize(bodyId[0])
    controller + action

  init: ->
    CIF.Initializer.exec('Common')
    if @currentPage()
      CIF.Initializer.exec(@currentPage())

# jQuery-3 prep (POAM-017b): the 'ready' EVENT was removed in jQuery 3 (and jquery-migrate
# does not restore it) — binding it via .on() would leave this app-wide dispatcher, and
# therefore ALL page JS, silently dead after the upgrade. $(handler) is the supported form
# on every jQuery version. 'page:load' was a vestigial Turbolinks event (no turbolinks here).
$ ->
  CIF.Initializer.init()