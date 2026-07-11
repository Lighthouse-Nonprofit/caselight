CIF.Custom_fieldsIndex = (function () {
  const _init = () => _active_tab();

  var _active_tab = function () {
    const tab = window.location.href.split('tab')[1];
    if (tab === undefined) {
      return;
    }
    if (tab.substr(1) === 'all_ngo') {
      return $('a[href="#all-custom-form"]').tab('show');
    }
  };

  return { init: _init };
})();
