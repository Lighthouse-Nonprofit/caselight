# Incident Response Policy — CaseLight

_NIST 800-53: IR-1, IR-4, IR-6, IR-8. SOC 2: CC7.3, CC7.4, CC7.5. Owner: the operating nonprofit.
Review: annually and after any incident or tabletop exercise._

> **Production gate:** `SECURITY.md` requires "an incident/breach response plan with named owners"
> **before real client data**. This policy is the template; the operating org MUST fill in the
> **named owners and contact paths** below before go-live. Until then it is a documented plan, not an
> operating capability.

## Roles (org to assign named individuals + backups)
- **Incident Lead** — coordinates response, owns the decision log. _(name TBD)_
- **Technical Responder** — box/app access via SSM, log analysis, containment. _(name TBD)_
- **Privacy/Legal Owner** — breach-notification obligations for immigration/minor/health records.
  _(name TBD)_
- **Communications Owner** — org leadership + affected-party notification. _(name TBD)_

## Detection (what signals an incident)
- **Security-event rows** in `AccessLog` (`login_failure`, `account_locked`, `access_denied`) — the
  primary application signal (CC7.2). Reviewed at least weekly; spikes (credential stuffing, lockout
  storms, authorization probing) escalate immediately.
- **CI/dependency alerts** — Dependabot + the failing SAST/secret gates.
- **Infra signals** (inherited) — host/network/proxy monitoring, WAF alerts.

## Response steps (IR-4)
1. **Declare & triage** — Incident Lead classifies severity; start the decision log.
2. **Contain** — disable affected accounts (`disable` flag), flip enforcement flags if authorization
   is implicated, block source IPs at the proxy/SG, or take the box off public reachability (it is
   normally reachable only via the SSM tunnel, which aids containment).
3. **Preserve evidence** — `AccessLog` is append-only; snapshot the EBS volume; export the relevant
   audit window (do **not** purge during an incident — retention purges stay manual for this reason).
4. **Eradicate & recover** — patch/rotate (credentials, AR-Encryption keys if key compromise is
   suspected), restore from a verified encrypted backup, redeploy via `bootstrap.sh`.
5. **Notify (IR-6)** — Privacy/Legal Owner determines breach-notification duties. **Real records here
   are among the most sensitive that exist** (refugee/asylee status, minors, health, gov IDs) — treat
   any confidentiality breach as a safety risk to vulnerable people and notify accordingly.
6. **Post-incident (IR-8)** — root-cause review; open POA&M items; update this policy and controls.

## Data-breach specifics
- Scope by tenant using the tenant-scoped audit trail and the PII inventory (`pii-inventory.md`) to
  identify exactly which fields/records were exposed.
- Because pilot data is **synthetic only**, a pilot-box incident carries no real-subject risk — but
  the same procedure is exercised so it is ready before real data.

## Enforcement / evidence anchors
`app/models/access_log.rb` (detection signal), `audit-logging.md`, `policies/data-retention.md`
(no-purge-during-incident), `OPERATIONS.md` (SSM containment, redeploy), `ssp.md` §5 (this plan is a
listed production gate).
