# BS5-Q3: Tom Select replaced select2 back in POAM-017c; the old Select2 spec helper drove
# select2-v3 DOM (.select2-choice / .select2-results) that no longer exists. This drives the
# Tom Select widget the same way a user does: open the control, click the option by text.
module TomSelect
  def tom_select_pick(value, wrapper_selector = '.ts-wrapper')
    first(wrapper_selector).find('.ts-control').click
    find('.ts-dropdown .option', text: value).click
  end
end
