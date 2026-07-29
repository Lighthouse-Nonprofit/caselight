// Datagrid filter-form styling (index pages). D2: ported to VANILLA — the classes are still
// JS-applied (the datagrid gem renders the inputs; teaching every grid class input_options
// would spray this across ~100 filter declarations) but no jQuery is involved anymore, and
// the .dataTables_empty branch left with the dataTables retirement.
(function () {
  function styleDatagridForm() {
    var indexes = [
      'clients-index',
      'families-index',
      'partners-index',
      'users-index',
      'progress_notes-index',
    ];
    if (indexes.indexOf(document.body.id) === -1) { return; }

    document.querySelectorAll('.integer_filter').forEach(function (el) {
      el.setAttribute('type', 'number');
    });

    document.querySelectorAll('.grid-form .datagrid-filter, .grid-form .domain-filter, .date-filter-group')
      .forEach(function (el) {
        if (!el.classList.contains('date-filter-group')) {
          el.classList.add('mb-3', 'col-12', 'col-sm-6', 'col-lg-4');
        }
        el.querySelectorAll(':scope > input').forEach(function (i) { i.classList.add('form-control'); });
        el.querySelectorAll(':scope > select').forEach(function (s) { s.classList.add('form-select'); });
      });

    document.querySelectorAll('.grid-form .datagrid-actions').forEach(function (el) {
      el.classList.add('col-12');
      el.querySelectorAll('input').forEach(function (i) { i.classList.add('btn', 'btn-primary'); });
      el.querySelectorAll('a').forEach(function (a) { a.classList.add('btn', 'btn-outline-secondary'); });
    });

    if (document.querySelector('table .noresults')) {
      document.querySelectorAll('.btn-export').forEach(function (b) { b.classList.add('disabled'); });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', styleDatagridForm);
  } else {
    styleDatagridForm();
  }
})();
