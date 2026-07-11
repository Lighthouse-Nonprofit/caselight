CIF.AdvancedFilterBuilder = class AdvancedFilterBuilder {
  constructor(element, fieldList, filterTranslation) {
    this.element = element;
    this.fieldList = fieldList;
    this.filterTranslation = filterTranslation;
  }

  initRule() {
    return $(this.element).queryBuilder(this.builderOption());
  }

  builderOption() {
    return {
      inputs_separator: ' AND ',
      icons: {
        remove_rule: 'fa fa-minus',
      },
      lang: {
        delete_rule: '',
        add_rule: this.filterTranslation.addFilter,
        add_group: this.filterTranslation.addGroup,
        delete_group: this.filterTranslation.deleteGroup,
        operators: {
          is_empty: 'is blank',
          is_not_empty: 'is not blank',
          equal: 'is',
          not_equal: 'is not',
          less: '<',
          less_or_equal: '<=',
          greater: '>',
          greater_or_equal: '>=',
          contains: 'includes',
          not_contains: 'excludes',
        },
      },
      filters: this.fieldList,
    };
  }
};
