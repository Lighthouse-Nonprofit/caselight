// D1: the agency modal gained a programs multi-select — enhance with Tom Select
// (partners/index.js precedent; dispatcher binds via the agencies-index body id).
CIF.AgenciesIndex = {
  init: function () {
    CIF.Select.init('select', { allowClear: true });
  },
};
