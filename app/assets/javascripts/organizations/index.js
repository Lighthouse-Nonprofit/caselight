CIF.OrganizationsIndex = (function () {
  const _init = () => _removeFooter();

  var _removeFooter = function () {
    if (window.location.href.includes('mho')) {
      return $('.padding-bottom').remove();
    }
  };

  return { init: _init };
})();
