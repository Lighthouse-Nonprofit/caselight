# Two-factor (MFA) enforcement toggle — FedRAMP IA-2(1).
#
# MFA itself is always AVAILABLE (any user can enroll via TwoFactorSettingsController). This flag only
# controls whether privileged accounts (admin + managers) are REQUIRED to have it: when true,
# ApplicationController#require_mfa_for_privileged redirects such a user to enroll before they can
# proceed. Defaults OFF so enabling MFA does not lock anyone out mid-pilot; flip to true (set
# ENFORCE_MFA_FOR_PRIVILEGED=true) once privileged users have enrolled.
Rails.application.config.x.enforce_mfa_for_privileged =
  ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENFORCE_MFA_FOR_PRIVILEGED', false))
