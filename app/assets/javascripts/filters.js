// jQuery-3 prep (POAM-017b): 'ready' event binding -> $(handler); see initializer.coffee.
$(function () {
  const indexes = [
    'clients-index',
    'families-index',
    'partners-index',
    'users-index',
    'progress_notes-index',
  ];
  const body = $('body').attr('id');

  if (indexes.indexOf(body) > -1) {
    $('.integer_filter').attr('type', 'number');
    $('.grid-form .datagrid-filter, .grid-form .domain-filter').each(function () {
      $(this).addClass('mb-3 col-12 col-sm-6 col-lg-4');
      $(this).children('input').addClass('form-control');
      return $(this).children('select').addClass('form-select');
    });

    $('.date-filter-group').each(function (index, element) {
      $(this).children('input').addClass('form-control');
      return $(this).children('select').addClass('form-select');
    });

    $('.grid-form .datagrid-actions').addClass('col-12');
    $('.grid-form .datagrid-actions input').addClass('btn btn-primary');
    $('.grid-form .datagrid-actions a').addClass('btn btn-outline-secondary');

    const noResult = $('table').find('.noresults');
    const noResultClient = $('table').find('.dataTables_empty');
    if (noResult.length === 1 || noResultClient.length === 1) {
      return $('.btn-export').addClass('disabled');
    }
  }
});
