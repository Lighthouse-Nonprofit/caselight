# PR 4 — referrals OUT. Bootstrap badge colouring for a referral's status.
module ReferralsHelper
  REFERRAL_STATUS_STYLE = {
    'Pending'   => 'text-bg-warning',
    'Accepted'  => 'text-bg-info',
    'Completed' => 'text-bg-success',
    'Declined'  => 'text-bg-secondary'
  }.freeze

  def referral_status_badge(referral)
    style = REFERRAL_STATUS_STYLE.fetch(referral.status, 'text-bg-light')
    content_tag(:span, referral.status.presence || t('referrals.unknown_status', default: '—'),
                class: "badge #{style}")
  end
end
