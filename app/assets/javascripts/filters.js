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
      $(this).addClass('form-group col-xs-12 col-sm-6 col-lg-4');
      return $(this).children('input, select').addClass('form-control');
    });

    $('.date-filter-group').each(function (index, element) {
      return $(this).children('input, select').addClass('form-control');
    });

    $('.grid-form .datagrid-actions').addClass('col-xs-12');
    $('.grid-form .datagrid-actions input').addClass('btn btn-primary');
    $('.grid-form .datagrid-actions a').addClass('btn btn-default');

    const noResult = $('table').find('.noresults');
    const noResultClient = $('table').find('.dataTables_empty');
    if (noResult.length === 1 || noResultClient.length === 1) {
      return $('.btn-export').addClass('disabled');
    }
  }
});
