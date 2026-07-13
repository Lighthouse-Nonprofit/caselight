module FeatureHelper
  # BS5-Q3: filling a date field focuses it and the vanillajs-datepicker panel stays open
  # over the submit button; cuprite (unlike PhantomJS) refuses to click through overlapping
  # elements. Blurring is not enough (the panel lingers) — hide any open panel outright;
  # the library re-shows it with inline styles on the next focus.
  def dismiss_datepicker
    page.execute_script(
      "document.querySelectorAll('.datepicker.active').forEach(function (el) {" \
      ' el.classList.remove("active"); el.style.display = "none"; })'
    )
  end

  def progress_note_info
    expect(page).to have_content(progress_note.decorate.client)
    expect(page).to have_content(progress_note.decorate.user)
    expect(page).to have_content(progress_note.decorate.user)
    expect(page).to have_content(progress_note.decorate.progress_note_type)
    expect(page).to have_content(progress_note.decorate.location)
    expect(page).to have_content(progress_note.other_location)
    expect(page).to have_content(progress_note.interventions.pluck(:action).join(', '))
    expect(page).to have_content(progress_note.decorate.material)
    expect(page).to have_content(progress_note.assessment_domains.pluck(:goal).join(', '))
  end
end
