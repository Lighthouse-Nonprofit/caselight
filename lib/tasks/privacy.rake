# lib/tasks/privacy.rake
#
# Phase 6 — subject-access / data-portability export (SOC 2 Privacy P5, GDPR-style SAR support).
# Operator-run (no new authenticated web surface on the pilot box; a self-serve UI is a Phase-7
# candidate). Produces ONE JSON document of a single client's records — AR Encryption decrypts on
# read, so the export contains the subject's actual data.
#
# ALLOWLIST-BASED by design: each section names its model + the associations included. Never
# `as_json` the world — that would sweep in staff PII and credential columns. Staff references stay
# as numeric ids. Uploaded files are listed by filename/identifier only (the operator pulls bytes
# separately if the request covers documents); the JSON stays a single reviewable artifact.
#
# Every run writes a values-free `record_exported` AccessLog row (AU-2) — the export FILE is the
# payload; the log never is. Output goes to tmp/exports/ (gitignored); move it out-of-band and
# delete it after delivery.

namespace :privacy do
  desc "Export one client's records as JSON (subject-access request). " \
       "Usage: rake privacy:subject_access_export TENANT=cases CLIENT=<id or slug>"
  task subject_access_export: :environment do
    tenant = ENV["TENANT"]
    ident  = ENV["CLIENT"]
    abort "[privacy:subject_access_export] TENANT= and CLIENT= are required" if tenant.blank? || ident.blank?
    abort "[privacy:subject_access_export] unknown tenant #{tenant}" unless Organization.exists?(short_name: tenant)

    Apartment::Tenant.switch(tenant) do
      client = Client.friendly.find(ident)

      # UX round 3 (C1): the four ignore_case name columns store the DOWNCASED match value —
      # attributes[] would export "maria". Overlay the readers (they return the original_*
      # display casing) and drop the internal sidecar columns from the artifact.
      client_attrs = client.attributes
      %w[given_name family_name local_given_name local_family_name].each do |col|
        client_attrs[col] = client.public_send(col)
        client_attrs.delete("original_#{col}")
      end

      export = {
        "exported_at"  => Time.current.iso8601,
        "tenant"       => tenant,
        "client"       => client_attrs,
        "cases"        => client.cases.map(&:attributes),
        "families"     => client.families.map(&:attributes),
        "enrollments"  => client.client_enrollments.map do |ce|
          ce.attributes.merge(
            "program_stream" => ce.program_stream.try(:name),
            "trackings"      => ce.client_enrollment_trackings.map(&:attributes),
            "leave_program"  => ce.leave_program.try(:attributes)
          )
        end,
        "assessments"  => client.assessments.map do |a|
          a.attributes.merge("assessment_domains" => a.assessment_domains.map(&:attributes))
        end,
        "case_notes"   => client.case_notes.map do |cn|
          cn.attributes.merge("domain_groups" => cn.case_note_domain_groups.map do |cndg|
            cndg.attributes.merge("attachment_files" => Array(cndg.attachments).map { |att| File.basename(att.path.to_s) })
          end)
        end,
        "progress_notes" => client.progress_notes.map do |pn|
          pn.attributes.merge("attachment_files" => pn.attachments.map { |att| File.basename(att.file.path.to_s) if att.file.present? }.compact)
        end,
        "tasks"        => client.tasks.map(&:attributes),
        "custom_forms" => client.custom_field_properties.includes(:custom_field).map do |cfp|
          {
            "form_title" => cfp.custom_field.try(:form_title),
            "created_at" => cfp.created_at,
            "updated_at" => cfp.updated_at,
            "properties" => cfp.properties,
            "attachment_files" => Array(cfp.attachments).map { |att| File.basename(att.path.to_s) }
          }
        end
      }

      dir = Rails.root.join("tmp", "exports")
      FileUtils.mkdir_p(dir)
      path = dir.join("subject_access_#{tenant}_client#{client.id}_#{Time.current.strftime('%Y%m%d%H%M%S')}.json")
      File.write(path, JSON.pretty_generate(export))

      # Values-free AU-2 evidence row. Direct create! (not the request-bound writers): this runs in
      # a rake with no HTTP request, and the export MUST NOT silently succeed unlogged — fail loud.
      # (U8 adds a request-less AccessLog.system_event! helper; converge on it once both merge.)
      log = AccessLog.create!(
        event_type: "record_exported",
        resource_type: "Client",
        resource_id: client.id.to_s,
        metadata: {
          "reason" => "subject_access_request",
          "task"   => "privacy:subject_access_export",
          "source" => "system"
        }
      )
      Rails.logger.info({ tag: "access_log", event_type: log.event_type, tenant: log.tenant,
                          resource_type: log.resource_type, resource_id: log.resource_id,
                          created_at: log.created_at.try(:iso8601) }.to_json)

      puts "[privacy:subject_access_export] wrote #{path}"
      puts "[privacy:subject_access_export] REMINDER: move the file out-of-band and delete it after delivery."
    end
  end
end
