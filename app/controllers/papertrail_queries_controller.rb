class PapertrailQueriesController < AdminController
  # Phase 5.6 (AC-3): the version data is loaded via the already-authorized DataTrackersController#index
  # AJAX; this is the shell view. Authorize :read, DataTracker to MIRROR data_trackers (one line) so the
  # action satisfies check_authorization and the cutover smoke/guard ship green -- rather than leaving it
  # default-open. Resolves the SHADOW-window finding for this controller.
  def index
    authorize! :read, DataTracker
  end
end
