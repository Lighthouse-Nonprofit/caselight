# frozen_string_literal: true
require 'rails_helper'

# Units 13-15 (Section 508 / WCAG 2.1 AA) -- SURFACE C: content-image alt STRINGS.
# The ABLE-screening images + admin upload-preview thumbnails get alt from new i18n keys
# (t('.question_image') / t('.image_alt')). Rendering those deep authenticated partials in a
# request spec is fragile, so this CI-included helper spec pins that every new key RESOLVES to its
# intended English default at its exact partial scope. If a key is deleted/moved, I18n.t returns
# the 'translation missing' marker and these fail.
RSpec.describe 'Surface C: content-image alt i18n keys', type: :helper do
  {
    'clients.answer_fields.question_image' => 'Screening question image',
    'able_screens.answer_submissions.able_screening_answers.answer_fields.question_image' => 'Screening question image',
    'able_screens.answer_submissions.able_screening_answers.form.question_image' => 'Screening question image',
    'able_screens.question_submissions.able_screening_questions.attachment_fields.image_alt' => 'Uploaded question image',
    'able_screens.question_submissions.stages.attachment_fields.image_alt' => 'Uploaded stage image'
  }.each do |key, expected|
    it "resolves #{key} to a meaningful, non-missing alt string" do
      value = I18n.t(key, locale: :en)
      expect(value).to eq(expected)
      expect(value).not_to include('translation missing')
    end
  end
end