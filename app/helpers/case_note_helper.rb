module CaseNoteHelper
  def edit_link(client, case_note)
    if policy(case_note).edit?
      link_to(edit_client_case_note_path(client, case_note), class: 'btn btn-primary', 'aria-label': t('shared.actions.edit', default: 'Edit')) do
        fa_icon('pencil', 'aria-hidden': true)
      end
    end
  end
end