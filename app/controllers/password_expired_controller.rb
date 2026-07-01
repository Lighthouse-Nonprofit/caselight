# frozen_string_literal: true

# Thin app subclass of devise-security's Devise::PasswordExpiredController, matching how CaseLight wraps
# its other devise controllers (sessions/registrations/passwords): it declares skip_authorization_check
# so the Phase-5.6 authorization coverage guard is satisfied via the SAME mechanism as those controllers
# (this page is gated by Devise's own authentication — a signed-in but password-expired user — not by
# CanCan, so CanCan authorization does not apply). View lookup falls through the ancestry to the gem's
# devise/password_expired templates. Routed via devise_for(controllers: { password_expired: 'password_expired' }).
class PasswordExpiredController < Devise::PasswordExpiredController
  skip_authorization_check
end
