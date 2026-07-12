# Puma config — replaced thin (2026-07-12). Sized for the pilot box (small EC2, 1–2 vCPU):
# single-mode (workers 0) keeps memory low and needs no preload/fork bookkeeping; the thread
# pool handles concurrent requests (thin was single-threaded, so 5 threads is a strict
# capacity upgrade). Scale later by setting WEB_CONCURRENCY>0 (clustered workers) and/or
# RAILS_MAX_THREADS in .env — no code change.
#
# Port stays 3000 in every environment: the Caddy proxy (prod) and the dev compose port
# mapping (127.0.0.1:3001->3000) both target it. RAILS_ENV comes from .env (production on
# the box) or the dev compose overlay (development).
threads_count = ENV.fetch('RAILS_MAX_THREADS', 5).to_i
threads threads_count, threads_count

workers ENV.fetch('WEB_CONCURRENCY', 0).to_i

port ENV.fetch('PORT', 3000)
environment ENV.fetch('RAILS_ENV', 'development')

# `touch tmp/restart.txt` restarts the server without a container bounce (dev convenience;
# no pidfile — the container's PID 1 is the process manager and dev tmp/ is root-owned).
plugin :tmp_restart
