// CIF.RuleBuilder — the hand-rolled, eval-free replacement for jQuery QueryBuilder 2.5.2
// (POAM-017f / Unit 18, PR 12A). QueryBuilder rendered its rule templates through doT, which
// compiles via new Function — the last unsafe-eval consumer in the bundle. This module renders
// the same DOM skeleton with plain DOM APIs instead.
//
// API mapping (old -> new), one instance per builder element:
//   $(el).queryBuilder({filters, lang, ...})   -> new CIF.RuleBuilder(el, {filters, lang, readOnly})
//   queryBuilder('getRules')                   -> instance.getRules()      // null when invalid
//   queryBuilder('setRules', rules)            -> instance.setRules(rules)
//   queryBuilder('addFilter', descriptors)     -> instance.addFilter(descriptors)
//   queryBuilder('removeFilter', ids)          -> instance.removeFilter(ids)
//   'afterCreateRuleFilters.queryBuilder'      -> 'rulebuilder:rule-rendered' (arg: rule element)
//
// Contracts deliberately preserved byte-for-byte (server + sibling-JS dependencies):
//   - Serialized rules: {condition, rules:[{id, field, type, input, operator, value}|group]}
//     in exactly that key order; integers emitted as JS numbers; between -> [lo, hi];
//     zero-input operators -> null. Parsed by AdvancedSearches::ClientBaseSqlBuilder and
//     stored in program_streams.rules (jsonb).
//   - getRules() returns null when validation fails (callers guard with $.isEmptyObject).
//   - DOM classes/ids match QueryBuilder's template skeleton (.rules-group-container,
//     .rule-container, .rule-filter-container select, button[data-add="rule"], the '-1'
//     placeholder option, one <optgroup> per descriptor optgroup label) — feature specs and
//     client_advanced_searches/index.js's remove-filter flow select against these.
//   - addFilter/removeFilter rebuild every rule's filter <select> as a FRESH node (QueryBuilder
//     setFilters behavior) so the consumers' idempotent CIF.Select.init re-Tom-Selects them.
//
// Divergences (documented): no drag-reorder (QueryBuilder's sortable plugin only ever threw
// MissingLibraryError — interact.js was never shipped — and rule order is SQL-irrelevant);
// setRules skips-and-warns on an unknown filter id instead of throwing ConfigError and killing
// the page module (matters on the read-only version-diff surfaces when a field is renamed).
//
// Security: every data-derived string (filter labels, optgroup labels, drop-list values —
// all tenant-authored) lands via createElement/textContent/option.value. No innerHTML, no
// $(htmlString), no eval, no new Function. The removal guard spec enforces this.
CIF.RuleBuilder = (function () {
  const PLACEHOLDER_VALUE = '-1';

  // Button labels are QueryBuilder's defaults — the views' translation data-attribute plumbing
  // always resolved to undefined, so the defaults are what has always rendered. The operator
  // labels are the app overrides every legacy option object carried as literals; baking them in
  // retires the four duplicated option blocks. ('between' was never overridden.)
  const DEFAULT_LANG = {
    add_rule: 'Add rule',
    add_group: 'Add group',
    delete_group: 'Delete',
    delete_rule: '',
    operators: {
      equal: 'is',
      not_equal: 'is not',
      less: '<',
      less_or_equal: '<=',
      greater: '>',
      greater_or_equal: '>=',
      contains: 'includes',
      not_contains: 'excludes',
      between: 'between',
      is_empty: 'is blank',
      is_not_empty: 'is not blank',
    },
  };

  // operator -> number of value inputs (the subset the app's FilterTypes descriptors use)
  const OPERATOR_INPUTS = {
    equal: 1,
    not_equal: 1,
    less: 1,
    less_or_equal: 1,
    greater: 1,
    greater_or_equal: 1,
    contains: 1,
    not_contains: 1,
    between: 2,
    is_empty: 0,
    is_not_empty: 0,
  };

  const INTEGER_RE = /^-?\d+$/;

  // jQuery-extend semantics for the lang option: undefined values must not override defaults
  // (the views' translation data-attribute plumbing has always resolved to undefined).
  const mergeLang = function (overrides) {
    const lang = {
      ...DEFAULT_LANG,
      operators: { ...DEFAULT_LANG.operators },
    };
    if (!overrides) return lang;
    for (const key of Object.keys(overrides)) {
      if (key === 'operators') continue;
      if (overrides[key] !== undefined) lang[key] = overrides[key];
    }
    for (const key of Object.keys(overrides.operators || {})) {
      if (overrides.operators[key] !== undefined) lang.operators[key] = overrides.operators[key];
    }
    return lang;
  };

  const el = function (tag, className) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    return node;
  };

  const button = function (className, dataAttr, dataValue, iconClass, label) {
    const btn = el('button', className);
    btn.type = 'button';
    btn.setAttribute(dataAttr, dataValue);
    const icon = el('i', iconClass);
    btn.appendChild(icon);
    if (label) btn.appendChild(document.createTextNode(` ${label}`));
    return btn;
  };

  // Tear down a Tom Select widget the consumer attached before we drop/replace its native
  // select (the only Tom Select awareness in this module — releases the widget's listeners;
  // its .ts-wrapper sibling goes away with the container children).
  const dropTomSelect = function (select) {
    if (select && select.tomselect) select.tomselect.destroy();
  };

  const clearContainer = function (container) {
    for (const select of container.querySelectorAll('select')) dropTomSelect(select);
    container.replaceChildren();
  };

  class RuleBuilder {
    constructor(element, options = {}) {
      this.el = element && element.jquery ? element[0] : element;
      this.filters = (options.filters || []).slice();
      this.lang = mergeLang(options.lang);
      this.readOnly = !!options.readOnly;
      this.rootId = this.el.id || 'rule_builder';
      this.counter = 0;

      this.el.classList.add('rule-builder');
      this.el.ruleBuilder = this;

      this.rootGroup = this._buildGroup(1);
      this.el.appendChild(this.rootGroup);
      if (!this.readOnly) {
        this._addRule(this._rulesList(this.rootGroup));
        this._bind();
      }
    }

    static get(target) {
      const node = target && target.jquery ? target[0] : target;
      return node ? node.ruleBuilder : undefined;
    }

    // ----- public API ------------------------------------------------------

    getRules() {
      this._clearErrors();
      const valid = this._validateGroup(this.rootGroup);
      if (!valid) return null;
      return this._readGroup(this.rootGroup);
    }

    setRules(rules) {
      const rulesList = this._rulesList(this.rootGroup);
      clearContainer(rulesList);
      if (!rules || typeof rules !== 'object') return;
      this._setGroup(this.rootGroup, rules);
      if (this.readOnly) this._disableAll();
    }

    addFilter(descriptors) {
      const list = Array.isArray(descriptors) ? descriptors : [descriptors];
      for (const descriptor of list) {
        if (descriptor && descriptor.id !== undefined) this.filters.push(descriptor);
      }
      this._rebuildFilterSelects();
    }

    removeFilter(ids) {
      const list = Array.isArray(ids) ? ids : [ids];
      const removed = new Set(list.map(String));
      this.filters = this.filters.filter((f) => !removed.has(String(f.id)));
      this._rebuildFilterSelects();
    }

    destroy() {
      clearContainer(this.el);
      this.el.classList.remove('rule-builder');
      delete this.el.ruleBuilder;
    }

    // ----- events ----------------------------------------------------------

    _bind() {
      const self = this;
      const $root = $(this.el);

      $root.on('click', 'button[data-add="rule"]', function () {
        const group = this.closest('.rules-group-container');
        self._addRule(self._rulesList(group));
      });

      $root.on('click', 'button[data-add="group"]', function () {
        const group = this.closest('.rules-group-container');
        const subgroup = self._buildGroup(2);
        self._rulesList(group).appendChild(subgroup);
        self._addRule(self._rulesList(subgroup));
      });

      $root.on('click', 'button[data-delete="group"]', function () {
        const group = this.closest('.rules-group-container');
        for (const select of group.querySelectorAll('select')) dropTomSelect(select);
        group.remove();
      });

      $root.on('click', 'button[data-delete="rule"]', function () {
        const rule = this.closest('.rule-container');
        for (const select of rule.querySelectorAll('select')) dropTomSelect(select);
        rule.remove();
      });

      $root.on('change', '.rule-filter-container select', function () {
        const rule = this.closest('.rule-container');
        self._applyFilterSelection(rule, this.value);
      });

      $root.on('change', '.rule-operator-container select', function () {
        const rule = this.closest('.rule-container');
        self._applyOperatorSelection(rule, this.value);
      });

      $root.on('change', '.group-conditions input[type="radio"]', function () {
        const conditions = this.closest('.group-conditions');
        for (const label of conditions.querySelectorAll('label')) {
          label.classList.toggle('active', label.contains(this) && this.checked);
        }
      });
    }

    _fireRuleRendered(ruleEl) {
      $(this.el).trigger('rulebuilder:rule-rendered', ruleEl);
    }

    // ----- DOM construction (QueryBuilder template skeleton parity) ---------

    _buildGroup(level) {
      const groupId = `${this.rootId}_group_${this.counter++}`;
      const group = el('div', 'rules-group-container');
      group.id = groupId;
      group.dataset.level = String(level);

      const header = el('div', 'rules-group-header');

      if (!this.readOnly) {
        const actions = el('div', 'btn-group float-end group-actions');
        actions.appendChild(
          button('btn btn-xs btn-success', 'data-add', 'rule', 'fa fa-plus', this.lang.add_rule),
        );
        actions.appendChild(
          button('btn btn-xs btn-success', 'data-add', 'group', 'fa fa-plus-circle', this.lang.add_group),
        );
        if (level > 1) {
          actions.appendChild(
            button('btn btn-xs btn-danger', 'data-delete', 'group', 'fa fa-times', this.lang.delete_group),
          );
        }
        header.appendChild(actions);
      }

      const conditions = el('div', 'btn-group group-conditions');
      for (const condition of ['AND', 'OR']) {
        const label = el('label', `btn btn-xs btn-primary${condition === 'AND' ? ' active' : ''}`);
        const radio = el('input');
        radio.type = 'radio';
        radio.name = `${groupId}_cond`;
        radio.value = condition;
        radio.checked = condition === 'AND';
        if (this.readOnly) radio.disabled = true;
        label.appendChild(radio);
        label.appendChild(document.createTextNode(condition));
        conditions.appendChild(label);
      }
      header.appendChild(conditions);

      const errorContainer = el('div', 'error-container');
      errorContainer.appendChild(el('i', 'fa fa-exclamation-triangle'));
      header.appendChild(errorContainer);

      group.appendChild(header);
      const body = el('div', 'rules-group-body');
      body.appendChild(el('div', 'rules-list'));
      group.appendChild(body);
      return group;
    }

    _rulesList(group) {
      // :scope > direct child — nested groups own their own rules-list
      return group.querySelector(':scope > .rules-group-body > .rules-list');
    }

    _addRule(rulesList) {
      const ruleId = `${this.rootId}_rule_${this.counter++}`;
      const rule = el('div', 'rule-container');
      rule.id = ruleId;

      const header = el('div', 'rule-header');
      if (!this.readOnly) {
        const actions = el('div', 'btn-group float-end rule-actions');
        actions.appendChild(
          button('btn btn-xs btn-danger', 'data-delete', 'rule', 'fa fa-minus', this.lang.delete_rule),
        );
        header.appendChild(actions);
      }
      rule.appendChild(header);

      const errorContainer = el('div', 'error-container');
      errorContainer.appendChild(el('i', 'fa fa-exclamation-triangle'));
      rule.appendChild(errorContainer);

      rule.appendChild(el('div', 'rule-filter-container'));
      rule.appendChild(el('div', 'rule-operator-container'));
      rule.appendChild(el('div', 'rule-value-container'));

      rule.querySelector('.rule-filter-container').appendChild(this._buildFilterSelect(ruleId));
      rulesList.appendChild(rule);
      this._fireRuleRendered(rule);
      return rule;
    }

    _buildFilterSelect(ruleId, selectedId) {
      const select = el('select', 'form-select');
      select.name = `${ruleId}_filter`;
      const placeholder = el('option');
      placeholder.value = PLACEHOLDER_VALUE;
      placeholder.textContent = '------';
      select.appendChild(placeholder);

      // one <optgroup> per distinct optgroup label, options in filter-list order —
      // client_advanced_searches' remove-filter flow scans these optgroups by label text
      const optgroups = new Map();
      for (const descriptor of this.filters) {
        let parent = select;
        if (descriptor.optgroup) {
          if (!optgroups.has(descriptor.optgroup)) {
            const group = el('optgroup');
            group.label = descriptor.optgroup;
            select.appendChild(group);
            optgroups.set(descriptor.optgroup, group);
          }
          parent = optgroups.get(descriptor.optgroup);
        }
        const option = el('option');
        option.value = String(descriptor.id);
        option.textContent = descriptor.label !== undefined ? String(descriptor.label) : String(descriptor.id);
        parent.appendChild(option);
      }
      if (selectedId !== undefined) select.value = String(selectedId);
      if (this.readOnly) select.disabled = true;
      return select;
    }

    _findFilter(id) {
      return this.filters.find((f) => String(f.id) === String(id));
    }

    _applyFilterSelection(rule, filterId) {
      const operatorContainer = rule.querySelector('.rule-operator-container');
      const valueContainer = rule.querySelector('.rule-value-container');
      clearContainer(operatorContainer);
      clearContainer(valueContainer);
      delete rule.dataset.filterId;

      const descriptor = this._findFilter(filterId);
      if (!descriptor) return; // '-1' placeholder or removed filter

      rule.dataset.filterId = String(descriptor.id);
      const operatorSelect = el('select', 'form-select');
      operatorSelect.name = `${rule.id}_operator`;
      for (const operator of descriptor.operators || []) {
        const option = el('option');
        option.value = operator;
        option.textContent = this.lang.operators[operator] !== undefined ? this.lang.operators[operator] : operator;
        operatorSelect.appendChild(option);
      }
      if (this.readOnly) operatorSelect.disabled = true;
      operatorContainer.appendChild(operatorSelect);

      const firstOperator = (descriptor.operators || [])[0];
      if (firstOperator) this._buildValueInputs(rule, descriptor, firstOperator);
    }

    _applyOperatorSelection(rule, operator) {
      const descriptor = this._findFilter(rule.dataset.filterId);
      if (!descriptor) return;
      const valueContainer = rule.querySelector('.rule-value-container');
      const wanted = OPERATOR_INPUTS[operator] !== undefined ? OPERATOR_INPUTS[operator] : 1;
      const current = valueContainer.querySelectorAll('input, select').length;
      // QueryBuilder parity: preserve the typed value when the input arity is unchanged
      if (wanted === current) return;
      this._buildValueInputs(rule, descriptor, operator);
    }

    _buildValueInputs(rule, descriptor, operator) {
      const valueContainer = rule.querySelector('.rule-value-container');
      clearContainer(valueContainer);
      const inputs = OPERATOR_INPUTS[operator] !== undefined ? OPERATOR_INPUTS[operator] : 1;
      if (inputs === 0) return;

      for (let index = 0; index < inputs; index++) {
        if (index > 0) valueContainer.appendChild(document.createTextNode(' AND '));
        valueContainer.appendChild(this._buildValueInput(rule, descriptor, index));
      }
    }

    _buildValueInput(rule, descriptor, index) {
      const name = `${rule.id}_value_${index}`;

      if (descriptor.input === 'select') {
        const select = el('select', 'form-select');
        select.name = name;
        this._appendValueOptions(select, descriptor.values);
        if (this.readOnly) select.disabled = true;
        return select;
      }

      const input = el('input', 'form-control');
      input.name = name;
      input.type = descriptor.type === 'integer' ? 'number' : 'text';
      if (this.readOnly) input.disabled = true;
      if (descriptor.plugin === 'datepicker') {
        // POAM-017g flip: vanillajs-datepicker via the shared adapter (same ISO yyyy-mm-dd
        // defaults as the global init); accepts the FilterTypes descriptor's plugin_config hash.
        CIF.DatePicker.attach(input, descriptor.plugin_config || {});
      }
      return input;
    }

    // FilterTypes emits two values shapes: a plain object {value: label, ...} (gender,
    // case_type) and an array of one-key objects [{value: label}, ...] (statuses, provinces,
    // users, ...). Render both, insertion-ordered.
    _appendValueOptions(select, values) {
      const appendOption = (value, label) => {
        const option = el('option');
        option.value = String(value);
        option.textContent = String(label);
        select.appendChild(option);
      };
      if (Array.isArray(values)) {
        for (const entry of values) {
          if (entry && typeof entry === 'object') {
            for (const key of Object.keys(entry)) appendOption(key, entry[key]);
          } else if (entry !== undefined && entry !== null) {
            appendOption(entry, entry);
          }
        }
      } else if (values && typeof values === 'object') {
        for (const key of Object.keys(values)) appendOption(key, values[key]);
      }
    }

    _rebuildFilterSelects() {
      for (const container of this.el.querySelectorAll('.rule-filter-container')) {
        const rule = container.closest('.rule-container');
        const previous = container.querySelector('select');
        const selected = previous ? previous.value : undefined;
        clearContainer(container);
        const fresh = this._buildFilterSelect(rule.id, selected);
        // a removed filter (or none) falls back to the placeholder
        if (fresh.value === '') fresh.value = PLACEHOLDER_VALUE;
        container.appendChild(fresh);
        this._fireRuleRendered(rule);
      }
    }

    // ----- serialization -----------------------------------------------------

    _groupCondition(group) {
      const checked = group.querySelector(
        ':scope > .rules-group-header .group-conditions input[type="radio"]:checked',
      );
      return checked ? checked.value : 'AND';
    }

    _readGroup(group) {
      const rules = [];
      for (const child of this._rulesList(group).children) {
        if (child.classList.contains('rule-container')) {
          rules.push(this._readRule(child));
        } else if (child.classList.contains('rules-group-container')) {
          rules.push(this._readGroup(child));
        }
      }
      // key order matters: serialized bytes must match QueryBuilder's output
      return { condition: this._groupCondition(group), rules };
    }

    _readRule(rule) {
      const descriptor = this._findFilter(rule.dataset.filterId);
      const operatorSelect = rule.querySelector('.rule-operator-container select');
      const operator = operatorSelect ? operatorSelect.value : undefined;
      return {
        id: descriptor.id,
        field: descriptor.id,
        type: descriptor.type,
        input: descriptor.input !== undefined ? descriptor.input : descriptor.type === 'integer' ? 'number' : 'text',
        operator,
        value: this._readValue(rule, descriptor, operator),
      };
    }

    _readValue(rule, descriptor, operator) {
      const inputs = OPERATOR_INPUTS[operator] !== undefined ? OPERATOR_INPUTS[operator] : 1;
      if (inputs === 0) return null;
      const fields = rule.querySelectorAll('.rule-value-container input, .rule-value-container select');
      const coerce = (raw) => {
        // QueryBuilder parity: integer fields emit JS numbers when the string is integral
        if (descriptor.type === 'integer' && INTEGER_RE.test(raw)) return parseInt(raw, 10);
        return raw;
      };
      if (inputs === 2) return [coerce(fields[0] ? fields[0].value : ''), coerce(fields[1] ? fields[1].value : '')];
      return coerce(fields[0] ? fields[0].value : '');
    }

    // ----- deserialization ---------------------------------------------------

    _setGroup(group, data) {
      const condition = data.condition === 'OR' ? 'OR' : 'AND';
      for (const radio of group.querySelectorAll(
        ':scope > .rules-group-header .group-conditions input[type="radio"]',
      )) {
        radio.checked = radio.value === condition;
        radio.closest('label').classList.toggle('active', radio.checked);
      }
      for (const entry of data.rules || []) {
        if (entry && Array.isArray(entry.rules)) {
          const subgroup = this._buildGroup(2);
          this._rulesList(group).appendChild(subgroup);
          this._setGroup(subgroup, entry);
        } else if (entry) {
          this._setRule(group, entry);
        }
      }
    }

    _setRule(group, data) {
      const descriptor = this._findFilter(data.id !== undefined ? data.id : data.field);
      if (!descriptor) {
        // deliberate divergence from QueryBuilder's ConfigError: a renamed/removed field must
        // not blank the whole page module (read-only version diffs render historic rules)
        // eslint-disable-next-line no-console
        console.warn('CIF.RuleBuilder: skipping rule for unknown filter', data.id !== undefined ? data.id : data.field);
        return;
      }
      const rule = this._addRule(this._rulesList(group));
      const filterSelect = rule.querySelector('.rule-filter-container select');
      filterSelect.value = String(descriptor.id);
      this._applyFilterSelection(rule, descriptor.id);

      const operatorSelect = rule.querySelector('.rule-operator-container select');
      if (operatorSelect && data.operator !== undefined && (descriptor.operators || []).includes(data.operator)) {
        operatorSelect.value = data.operator;
        this._applyOperatorSelection(rule, data.operator);
      }
      const operator = operatorSelect ? operatorSelect.value : undefined;

      const inputs = OPERATOR_INPUTS[operator] !== undefined ? OPERATOR_INPUTS[operator] : 1;
      if (inputs > 0) {
        const fields = rule.querySelectorAll('.rule-value-container input, .rule-value-container select');
        const values = inputs === 2 && Array.isArray(data.value) ? data.value : [data.value];
        for (let index = 0; index < inputs; index++) {
          const field = fields[index];
          const value = values[index];
          if (field && value !== undefined && value !== null) field.value = String(value);
        }
      }
      // re-announce: filter/operator/value selects were rebuilt after the initial render
      this._fireRuleRendered(rule);
    }

    // ----- validation ---------------------------------------------------------

    _clearErrors() {
      for (const node of this.el.querySelectorAll('.has-error')) node.classList.remove('has-error');
    }

    _markError(node, message) {
      node.classList.add('has-error');
      const icon = node.querySelector(':scope > .error-container, :scope > .rules-group-header > .error-container');
      if (icon) icon.title = message;
    }

    _validateGroup(group) {
      let valid = true;
      const children = Array.from(this._rulesList(group).children);
      if (children.length === 0) {
        this._markError(group, 'The group is empty');
        return false;
      }
      for (const child of children) {
        if (child.classList.contains('rules-group-container')) {
          if (!this._validateGroup(child)) valid = false;
        } else if (child.classList.contains('rule-container')) {
          if (!this._validateRule(child)) valid = false;
        }
      }
      return valid;
    }

    _validateRule(rule) {
      const descriptor = this._findFilter(rule.dataset.filterId);
      if (!descriptor) {
        this._markError(rule, 'No filter selected');
        return false;
      }
      const operatorSelect = rule.querySelector('.rule-operator-container select');
      const operator = operatorSelect ? operatorSelect.value : undefined;
      const inputs = OPERATOR_INPUTS[operator] !== undefined ? OPERATOR_INPUTS[operator] : 1;
      if (inputs === 0) return true;

      const fields = rule.querySelectorAll('.rule-value-container input, .rule-value-container select');
      for (let index = 0; index < inputs; index++) {
        const raw = fields[index] ? fields[index].value : '';
        if (raw === '') {
          this._markError(rule, 'Empty value');
          return false;
        }
        if (descriptor.type === 'integer' && !INTEGER_RE.test(raw)) {
          this._markError(rule, 'Not a valid number');
          return false;
        }
      }
      return true;
    }

    // ----- read-only helpers ----------------------------------------------------

    _disableAll() {
      for (const node of this.el.querySelectorAll('input, select, textarea')) node.disabled = true;
    }
  }

  return RuleBuilder;
})();
