class ProgressNoteDecorator < Draper::Decorator
  delegate_all

  def client
    model.client.name
  end

  def client_slug_id
    model.client.slug
  end

  def user
    model.user.name
  end

  # NB: this deliberately returns the STRING note_type for display, so callers that need the
  # record (or its category) must go through the model -- see #curriculum_note? below.
  def progress_note_type
    model.progress_note_type.note_type if model.progress_note_type
  end

  def material
    model.material.status if model.material
  end

  def location
    model.location.name if model.location
  end

  # Program (curriculum & session) notes carry Interventions / Equipment-Materials /
  # Goals Addressed; contact and general notes do not.
  def curriculum_note?
    model.progress_note_type&.curriculum? || false
  end
end
