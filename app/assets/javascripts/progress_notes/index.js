// D2: thin CIF.RecordTable page module (was a dataTables/niceScroll clone — see shared/record_table.js).
CIF.Progress_notesIndex = {
  init: function () {
    CIF.Select.init('select', { allowClear: true });
    CIF.RecordTable.init('table.progress-notes', '.progress_notes-table');
  }
};
