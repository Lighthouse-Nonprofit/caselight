# frozen_string_literal: true

# DownloadsController — Phase 6 (POAM-SC28-UPLOADS close; NIST AC-3/AC-6, SC-28).
#
# Generalizes the Phase-5.3 assessments#download_attachment pattern to every remaining CarrierWave
# mount that was still raw byte-served from public/uploads at guessable URLs with NO authorization:
# progress-note/able-screening files+images (Attachment), custom-form attachments
# (CustomFieldProperty), case-note attachments (CaseNoteDomainGroup) and form-builder attachments
# (FormBuilderAttachment, polymorphic over CFP/enrollment/tracking/leave-program).
# UploadsStaticGuard now denies ALL of /uploads/** (except the public org logo), so this controller
# is the only serve path.
#
# Authorization model (record-auth in a before_action so the Phase-5.6 check_authorization sees an
# authorize! on every completed action; late 404s happen after authz):
#   * attachment               -> authorize! :read on the PARENT (progress_note / able_screening_
#                                 question). Deliberately NOT on Attachment itself: ec/fc/kc manager
#                                 have no Attachment rule but legitimately read progress notes.
#   * custom_field_property    -> authorize! :read on the custom_formable + the Phase-5.3
#                                 custom-field sensitivity gate (record-aware, break-glass honoring).
#   * case_note_domain_group   -> authorize! :read on the case_note, + the derived domain-GROUP
#                                 sensitivity gate (POAM-013, closed): the viewer's visible domain
#                                 levels must cover EVERY domain in the group — the attachment
#                                 belongs to the whole section and cannot be attributed to a single
#                                 domain, so the most sensitive domain governs. Nil group fails closed.
#   * form_builder_attachment  -> authorize! :read on the polymorphic form_buildable, + the CFP
#                                 sensitivity gate when the buildable is a CustomFieldProperty.
#
# Fail-closed: sensitivity denial -> STATIC 403 + values-free sensitive_field_denied AccessLog;
# any unexpected error after authz -> STATIC 403. File mounts serve with disposition 'attachment'
# (a served-inline upload is an XSS surface; the uploaders' extension allowlists contain no
# HTML/SVG, but attachment-disposition removes the class of risk). The image mount (screening
# question illustrations, images-only allowlist) serves inline so <img> tags keep rendering.
class DownloadsController < AdminController
  include SensitiveFields  # Phase 5.3 — visible_custom_field_ids_for (record-aware break-glass)

  REGISTRY = {
    'attachment' => {
      model: 'Attachment',
      mounts: { 'file' => { array: false }, 'image' => { array: false, inline: true } }
    },
    'custom_field_property' => {
      model: 'CustomFieldProperty',
      mounts: { 'attachments' => { array: true } }
    },
    'case_note_domain_group' => {
      model: 'CaseNoteDomainGroup',
      mounts: { 'attachments' => { array: true } }
    },
    'form_builder_attachment' => {
      model: 'FormBuilderAttachment',
      mounts: { 'file' => { array: true } }  # mount_uploaders — an ARRAY despite the singular name
    }
  }.freeze

  before_action :find_record
  before_action :authorize_record!

  def show
    return forbidden!('sensitivity') unless sensitivity_allows?

    uploader = resolve_uploader
    return not_found! if uploader.nil? || uploader.file.nil?

    if params[:version].present?
      # Static lookup (only :thumb exists) — params never reach the version dispatch or the path.
      return not_found! unless params[:version] == 'thumb' && mount_config[:inline]
      uploader = uploader.versions[:thumb]
      return not_found! if uploader.nil? || uploader.file.nil?
    end

    # Containment check: the path comes from CarrierWave's store (never from params), but verify it
    # resolves inside public/uploads before serving — belt-and-braces against any future uploader
    # misconfiguration (CWE-22).
    path = File.expand_path(uploader.path)
    uploads_root = File.expand_path(Rails.root.join('public', 'uploads'))
    return not_found! unless path.start_with?(uploads_root + File::SEPARATOR)

    # POAM-019 (PR B3) — verified-PDF inline viewing. `?disposition=inline` is honored ONLY when
    # the stored file PROVES it is a PDF (allowlisted .pdf extension AND %PDF- magic bytes);
    # anything else silently keeps the Phase-6 attachment discipline (a served-inline upload is
    # an XSS surface — PDF in a browser-native viewer is the one carve-out, and the response
    # carries `Content-Security-Policy: sandbox` so any active content the viewer honors runs in
    # a fully sandboxed, origin-less browsing context). Authorization and the sensitivity gates
    # above run IDENTICALLY on this path — inline is a serving mode, never an access mode.
    inline_pdf = params[:disposition] == 'inline' && verified_pdf?(path)
    response.headers['Content-Security-Policy'] = 'sandbox' if inline_pdf

    send_file path,
              filename: File.basename(path),
              disposition: (mount_config[:inline] || inline_pdf) ? 'inline' : 'attachment',
              type: inline_pdf ? 'application/pdf' : (uploader.content_type.presence || 'application/octet-stream')
  rescue StandardError => e
    Rails.logger.error("[downloads#show] failing closed: #{e.class}: #{e.message}")
    render template: 'errors/403', status: :forbidden, layout: false
  end

  private

  def registry_config
    REGISTRY.fetch(params[:record_type])  # route constraint guarantees membership
  end

  def mount_config
    registry_config[:mounts].fetch(params[:mount])
  end

  def find_record
    # Unknown mount for the type -> 404 BEFORE any authz (no record involved yet).
    return render(plain: 'Not found', status: :not_found, layout: false) unless registry_config[:mounts].key?(params[:mount])

    @record = registry_config[:model].constantize.find(params[:record_id])
  end

  # Record-level CanCan authorization against the READABLE PARENT. Raises CanCan::AccessDenied ->
  # the ApplicationController rescue (access_denied AccessLog + deny response), same as every other
  # controller. A nil parent (orphaned row) authorizes the record class itself — no rule grants
  # that broadly, so it denies.
  def authorize_record!
    case params[:record_type]
    when 'attachment'
      authorize! :read, (@record.progress_note || @record.able_screening_question || Attachment)
    when 'custom_field_property'
      authorize! :read, (@record.custom_formable || CustomFieldProperty)
    when 'case_note_domain_group'
      authorize! :read, (@record.case_note || CaseNoteDomainGroup)
    when 'form_builder_attachment'
      authorize! :read, (@record.form_buildable || FormBuilderAttachment)
    end
  end

  # Phase-5.3 field-level gate on top of record-auth: custom-form attachments are PART of the
  # custom-field value, so they follow the same visibility set as the rendered field. Case-note
  # attachments follow the derived domain-GROUP sensitivity (POAM-013) — see below.
  def sensitivity_allows?
    return case_note_domain_group_visible? if params[:record_type] == 'case_note_domain_group'

    cfp = case params[:record_type]
          when 'custom_field_property'  then @record
          when 'form_builder_attachment' then (@record.form_buildable if @record.form_buildable.is_a?(CustomFieldProperty))
          end
    return true if cfp.nil?

    visible_custom_field_ids_for(cfp.custom_formable).include?(cfp.custom_field_id)
  end

  # POAM-013 derived gate: sensitivity lives on Domain, not DomainGroup, and a case-note section
  # covers ALL of its group's domains — the attachment cannot be attributed to one domain, so the
  # viewer must be cleared for every domain in the group (most-sensitive governs). Nil group fails
  # closed (parity with the assessments nil-domain 403). An empty group has nothing sensitive
  # declared and passes on record-auth alone.
  def case_note_domain_group_visible?
    group = @record.domain_group
    return false if group.nil?

    levels = visible_domain_levels
    group.domains.all? { |domain| levels.include?(domain.sensitivity) }
  end

  # Explicit dispatch (not public_send(params[:mount])) — the route constraint already whitelists
  # the mount names, but static sends keep user input out of method dispatch entirely.
  def resolve_uploader
    value = case params[:mount]
            when 'file'        then @record.file
            when 'image'       then @record.image
            when 'attachments' then @record.attachments
            end
    mount_config[:array] ? Array(value)[params[:index].to_i] : value
  end

  def forbidden!(surface)
    AccessLog.security_event!(
      event_type: 'sensitive_field_denied',
      request:    request,
      user:       current_user,
      metadata:   {
        'surface'     => 'authorized_download',
        'record_type' => params[:record_type],
        'record_id'   => params[:record_id],
        'mount'       => params[:mount],
        'reason'      => surface
      }
    )
    render template: 'errors/403', status: :forbidden, layout: false
  end

  def not_found!
    render plain: 'Not found', status: :not_found, layout: false
  end

  # POAM-019 (PR B3): a file may serve inline ONLY when it proves it is a PDF — allowlisted
  # extension AND leading %PDF- magic bytes (a renamed non-PDF fails the sniff and stays an
  # attachment download). Any read error fails closed to attachment.
  def verified_pdf?(path)
    File.extname(path).casecmp('.pdf').zero? &&
      File.open(path, 'rb') { |f| f.read(5) } == '%PDF-'
  rescue StandardError
    false
  end
end
