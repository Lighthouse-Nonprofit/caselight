// HUB1 — school roster row-click navigation only. Body-id dispatch NOTE: this
// module is CIF.SchoolsRoster because 'roster' is a single word; entry pages
// (report_cards, roll_call) stay MODULE-FREE on purpose — CIF.Util.capitalize
// does not split underscores, so 'schools-report_cards' would dispatch to
// CIF.SchoolsReport_cards. Don't add modules under those names.
CIF.SchoolsRoster = {
  init: function () {
    CIF.RecordTable.init('table.school-roster', '.school-roster-table');
  }
};
