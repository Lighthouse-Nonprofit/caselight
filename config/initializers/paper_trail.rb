# Association tracking was extracted to the separate paper_trail-association_tracking gem (not
# installed) and is OFF by default, which is what we want — we version each record's own columns,
# all the SECURITY.md audit trail needs. paper_trail 12 removed PaperTrail.config.track_associations=,
# so we no longer set it explicitly. version_limit nil keeps every version.
PaperTrail.config.version_limit = nil

# Tag a who-did-it for non-web contexts (web requests set it via set_paper_trail_whodunnit).
# paper_trail 10 moved the module-level PaperTrail.whodunnit= to PaperTrail.request.whodunnit=.
if defined?(::Rails::Console)
  PaperTrail.request.whodunnit = "#{`whoami`.strip}@console"
elsif defined?(Rake) && Rake.respond_to?(:application) && Rake.application.name
  PaperTrail.request.whodunnit = "#{`whoami`.strip}@rake"
end
