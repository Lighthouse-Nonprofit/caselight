CIF.NotificationsIndex = (function () {
  const _init = () => _initFootable();

  var _initFootable = () => $('.footable').footable();

  return { init: _init };
})();
