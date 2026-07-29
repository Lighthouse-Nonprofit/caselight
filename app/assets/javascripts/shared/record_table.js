// D2 (grid modernization) — CIF.RecordTable: the ONE vanilla module behind every legacy
// datagrid table page. Replaces the five near-identical per-page modules that each ran
// jquery.dataTables with EVERY feature disabled (bSort/bFilter/bPaginate/bInfo all false —
// pure cosmetics: a fixed header + an x-scroll body) plus jquery.nicescroll on the scroll
// body. The replacement is the .record-grid pattern the clients/families indexes already
// ship: a native overflow container (.cl-table-scroll, caselight_theme/_tables.scss) with a
// position:sticky thead — no plugins, no wrappers, no cloned header tables.
//
// Row navigation is DELEGATED on tr[data-href] (datagrid/_row renders the attribute), so:
//   * no-results rows are naturally inert (they carry no data-href — the old modules
//     string-compared 'No results found' + its Khmer残 to decide whether to bind),
//   * clicks on real interactive elements inside a row still win.
CIF.RecordTable = {
  // tableSelector:   the datagrid <table> (e.g. 'table.users')
  // wrapperSelector: the scroll wrapper around it (e.g. '.users-table')
  init: function (tableSelector, wrapperSelector) {
    var wrapper = wrapperSelector && document.querySelector(wrapperSelector);
    if (wrapper) { wrapper.classList.add('cl-table-scroll'); }

    var table = document.querySelector(tableSelector);
    if (!table) { return; }
    table.addEventListener('click', function (e) {
      if (e.target.closest('a, button, .btn, input, select, label')) { return; }
      var row = e.target.closest('tr[data-href]');
      if (row && row.dataset.href) { window.location = row.dataset.href; }
    });
  }
};
