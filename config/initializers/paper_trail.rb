# paper_trail 8.x notes (Rails 5 upgrade):
# - track_associations was extracted to the separate paper_trail-association_tracking gem
#   (not installed). We only version each record's own columns, which is all the SECURITY.md
#   audit trail needs, so association tracking is intentionally off.
# - version_limit nil keeps every version.
PaperTrail.config.track_associations = false
PaperTrail.config.version_limit = nil

PaperTrail::Rails::Engine.eager_load!

# Tag a who-did-it for non-web contexts (web requests set it via set_paper_trail_whodunnit).
# paper_trail 10 moved the module-level PaperTrail.whodunnit= to PaperTrail.request.whodunnit=.
if defined?(::Rails::Console)
  PaperTrail.request.whodunnit = "#{`whoami`.strip}@console"
elsif defined?(Rake) && Rake.respond_to?(:application) && Rake.application.name
  PaperTrail.request.whodunnit = "#{`whoami`.strip}@rake"
end
