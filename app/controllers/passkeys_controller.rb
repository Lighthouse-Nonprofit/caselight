# Self-service passkey (WebAuthn) management + the logged-in REGISTRATION ceremony. FedRAMP IA-2.
#
# Inherits AdminController (like TwoFactorSettingsController) so it runs authenticate_user! and gets the
# shared authenticated chrome (notify_user / set_sidebar_basic_info) — the management page renders inside
# the app layout.
#
# This controller is ADDITIVE: it only registers NEW credentials for an already-signed-in user. The
# passwordless LOGIN ceremony (which actually signs a user in) lives in SessionsController and is the
# only place a passkey grants a session.
#
# Ceremony (two round-trips):
#   1. POST /passkeys/options -> #create_options: issues PublicKeyCredentialCreationOptions, stashes the
#      challenge in the session.
#   2. navigator.credentials.create(...) in the browser -> POST /passkeys -> #create: verifies the
#      attestation against the stashed challenge and persists the credential.
class PasskeysController < AdminController
  include WebauthnRelyingParty

  # The JSON ceremony POSTs send X-CSRF-Token from the page meta tag (see the inline JS); the default
  # AdminController forgery protection (raise on mismatch) still applies.
  def show
    @credentials = current_user.webauthn_credentials.order(:created_at)
  end

  # Issue registration options + stash the challenge.
  def create_options
    current_user.update!(webauthn_id: WebAuthn.generate_user_id) if current_user.webauthn_id.blank?

    options = relying_party.options_for_registration(
      user: {
        id:           current_user.webauthn_id,
        name:         current_user.email,
        display_name: current_user.try(:name).presence || current_user.email
      },
      exclude:               current_user.webauthn_credentials.pluck(:external_id),
      authenticator_selection: { user_verification: 'preferred', resident_key: 'preferred' }
    )

    session[:webauthn_registration_challenge] = options.challenge
    render json: options
  end

  # Verify the attestation and persist the credential.
  def create
    challenge = session.delete(:webauthn_registration_challenge)
    return render(json: { error: 'No registration in progress.' }, status: :unprocessable_entity) if challenge.blank?

    webauthn_credential = relying_party.verify_registration(
      credential_param, challenge, user_verification: true
    )

    credential = current_user.webauthn_credentials.create!(
      external_id: webauthn_credential.id,
      public_key:  webauthn_credential.public_key,
      sign_count:  webauthn_credential.sign_count,
      nickname:    params[:nickname].to_s.strip.presence || 'Passkey'
    )

    render json: { status: 'ok', id: credential.id, nickname: credential.nickname }
  rescue WebAuthn::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  rescue ActiveRecord::RecordInvalid => e
    render json: { error: e.record.errors.full_messages.to_sentence }, status: :unprocessable_entity
  end

  def destroy
    current_user.webauthn_credentials.find(params[:id]).destroy
    redirect_to passkeys_path, notice: t('passkeys.removed', default: 'Passkey removed.')
  end

  private

  # The attestation credential from navigator.credentials.create(...). Permit the exact WebAuthn
  # registration shape (no `permit!` — Brakeman mass-assignment) and hand a plain string-keyed hash to
  # WebAuthn::RelyingParty#verify_registration. `clientExtensionResults` is permitted as an arbitrary
  # sub-hash because its keys are extension-defined; it is not persisted.
  def credential_param
    params.require(:credential)
          .permit(:id, :rawId, :type, :authenticatorAttachment,
                  response: %i[clientDataJSON attestationObject],
                  clientExtensionResults: {})
          .to_h
  end
end
