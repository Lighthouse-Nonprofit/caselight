module CaseNoteHelper
  # UX round 3 (D1/R7): pre-select the domain picker for sections that carry content —
  # persisted rows with a note/tasks/attachments, or a re-rendered submission with input.
  def case_note_section_selected?(cndg)
    cndg.note.present? ||
      Array(cndg.attachments).reject(&:blank?).any? ||
      (cndg.persisted? && cndg.tasks.any?)
  end

  def edit_link(client, case_note)
    if policy(case_note).edit?
      link_to(edit_client_case_note_path(client, case_note), class: 'btn btn-primary', 'aria-label': t('shared.actions.edit', default: 'Edit')) do
        fa_icon('pencil', 'aria-hidden': true)
      end
    end
  end
end