CIF.Common = {
  init() {
    this.hideDynamicOperator();
    this.validateFilterNumber();
    this.customCheckBox();
    this.initNotification();
    return this.autoCollapseManagMenu();
  },

  customCheckBox() {
    $('.i-check-red').iCheck({
      radioClass: 'iradio_square-red',
    });

    $('.i-check-brown').iCheck({
      radioClass: 'iradio_square-brown',
    });

    $('.i-check-orange').iCheck({
      radioClass: 'iradio_square-orange',
    });

    return $('.i-checks').iCheck({
      checkboxClass: 'icheckbox_square-green',
      radioClass: 'iradio_square-green',
    });
  },

  autoCollapseManagMenu() {
    const active = $('.nav-second-level').find('.active');
    const navThirdActive = $('.nav-third-level').find('.active');
    if (active.length > 0) {
      $('#manage').trigger('click');
      if (navThirdActive.length > 0) {
        return setTimeout(() => $('#pro-nav').trigger('click'), 400);
      }
    }
  },

  hideDynamicOperator() {
    return $('.dynamic_filter').find('option[value="=~"]').remove('option');
  },

  validateFilterNumber() {
    return $(window).load(() => $('input[type="number"]').attr('min', '0'));
  },

  initNotification() {
    const messageOption = {
      closeButton: true,
      debug: true,
      progressBar: true,
      positionClass: 'toast-top-center',
      showDuration: '400',
      hideDuration: '1000',
      timeOut: '7000',
      extendedTimeOut: '1000',
      showEasing: 'swing',
      hideEasing: 'linear',
      showMethod: 'fadeIn',
      hideMethod: 'fadeOut',
    };
    // `#wrapper` is rendered on every page by the app layout, but guard anyway: jQuery `.data()` returns
    // undefined for an empty set, and `Object.keys(undefined)` throws -- which would abort CIF.Common.init
    // and, with it, EVERY page module that runs after it (the calendar, etc.). Fail safe to `{}`.
    const messageInfo = $('#wrapper').data() || {};
    if (Object.keys(messageInfo).length > 0) {
      if (messageInfo.messageType === 'notice') {
        return toastr.success(messageInfo.message, '', messageOption);
      } else if (messageInfo.messageType === 'alert') {
        return toastr.error(messageInfo.message, '', messageOption);
      }
    }
  },
};
