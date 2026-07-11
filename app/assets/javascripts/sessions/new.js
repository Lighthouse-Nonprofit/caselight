CIF.SessionsNew = CIF.SessionsCreate = (function () {
  const _init = () => _removeUnsupportLanguageNotification();

  var _removeUnsupportLanguageNotification = function () {
    const locale = $('.alert-warning').data('locale');
    if (locale === 'en') {
      return;
    }
    const notifyByPanel = localStorage.getItem('notifyByPanel') || '';
    $('.alert-warning').removeClass('hidden');
    if (notifyByPanel === 'yes') {
      return $('.alert-warning').addClass('hidden');
    } else {
      return localStorage.setItem('notifyByPanel', 'yes');
    }
  };

  return { init: _init };
})();
