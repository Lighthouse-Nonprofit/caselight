# SECURITY.md — CaseLight data-handling posture & production gate

Read this before any real data touches a CaseLight deployment. It is the plain-language companion to
the formal control set in [`docs/compliance/`](docs/compliance/) — start with
[`docs/compliance/ssp.md`](docs/compliance/ssp.md) (System Security Plan) and
[`docs/compliance/control-matrix.md`](docs/compliance/control-matrix.md).

## Why this matters more than usual

The case-file taxonomy holds among the most sensitive PII categories that exist, stacked together:
refugee/asylee **immigration status and documents**, **minors'** records (school, IEP, disciplinary),
**health and mental-health** needs, and government **identity documents**. A breach here is not an
embarrassment — it is a safety risk to vulnerable people, several of whom may be minors or have
protection concerns.

## Stack posture

The application stack is current and supported (Ruby 4.0 / Rails 8.0 / PostgreSQL 17 / MongoDB 6.0 /
Redis 7 / Sidekiq 7.3; see `docs/compliance/ssp.md` §1 for the authoritative pin). It receives upstream
security patches, and the **application-layer hardening program (Phases 0–7) is complete**: secure-SDLC
CI gates, transport/header hardening, MFA + lockout + throttling, comprehensive access + change
auditing, field-level PII encryption at rest, role- and field-level authorization with break-glass, a
full privacy/data-lifecycle (retention, deletion, subject-access export), and the SSP + control matrix
+ policies + reproducible evidence that document it.

## Hard rule for the pilot

**Synthetic or representative data only.** No real client records on the evaluation box during the
pilot. `ffaker` is a dependency; generate realistic fake families. This removes the breach blast radius
while fit is assessed and lets staff test workflows honestly.

## Pilot baseline (meet all before even synthetic go-live with staff)

- [ ] EBS volume encrypted at rest.
- [ ] Security group locked: shell access via SSM only (zero inbound); app (443) restricted to pilot
      users' IPs or behind a VPN. Postgres/Mongo/Redis ports never exposed (compose binds the app to
      `127.0.0.1`).
- [ ] HTTPS only (Caddy / Let's Encrypt); HTTP redirects. *(Documented; stand up before staff use.)*
- [ ] Strong Devise passwords; no shared logins — one `User` per staff member so the audit trail is
      meaningful (enforced: complexity + no-reuse; see `policies/access-control.md`).
- [ ] Automated EBS snapshots (daily), retained encrypted.
- [ ] `noindex` / not linked publicly; do not let it get crawled.
- [ ] Ideally an isolated AWS account, or at least a dedicated VPC.

## Production gate (real client data) — a separate, deliberate decision

Do not slide from "pilot worked" into "now it has real data" without an explicit decision. The
application-layer controls are in place; production additionally requires a **documented risk
acceptance with compensating controls**. The authoritative, itemized gate is
[`docs/compliance/ssp.md`](docs/compliance/ssp.md) §5. In summary, before real records:

- **KMS-managed encryption keys** — replace the pilot's `secret_key_base`-derived ActiveRecord
  Encryption keys with independent ENV/KMS keys; do not disable `support_unencrypted_data` until every
  tenant is backfilled and `rake encryption:verify` passes across every tier.
- **Encryption in transit and at rest, end to end** — TLS in operation (Caddy), field-level + disk
  encryption (in place), and the history-store scrub run on the box (`history:verify_*` PASS).
- **`cases.exit_note`** plaintext copy encrypted (POAM-012).
- **A data retention/deletion policy with the live-record window set** (immigration and minor records
  especially) — currently TBD-blocking in `policies/data-retention.md`.
- **Network isolation** (private subnet, reachable only via the proxy / VPN) and a **WAF** in front.
- **Encrypted, tested backups** with a defined retention and a **restore drill**.
- **Role-based access** with the "read first" wellness flags and "emergencies only" contacts enforced
  as restricted fields (in place: `SensitivityPolicy` + break-glass), and the enforcement flags flipped
  per environment after an AccessReview shadow-window review.
- **The Mongo history store verified as a real, tamper-resistant audit trail** (in place; WORM tier
  inherited).
- **An incident/breach response plan with named owners** — template in
  `policies/incident-response.md`; owners must be assigned.

## Compliance framing (for the org and any funder questions)

AWS provides encryption, isolation, and physical security as **infrastructure** controls, but a SOC 2
(or similar) attestation is about the **operating entity and its processes**, not the box. The org owns
the application-layer controls (access, retention, breach response) — and CaseLight now hands you those
controls **documented and evidence-backed** (`docs/compliance/`). Hosting on AWS does not transfer that
ownership. If a funder or partner asks "is it secure," the honest, strong answer is: "the infrastructure
is sound; here is our documented application-layer control set, our reproducible evidence, and our
explicit risk acceptance for anything not yet met." That is a far stronger position than implying the
platform is something it is not.

## Reporting a vulnerability

CaseLight is AGPL-3.0 free software maintained by Lighthouse Nonprofit Technologies for underserved
nonprofits. If you find a security issue, please report it privately to the maintainers rather than
opening a public issue, and allow reasonable time to remediate before disclosure. Known findings and
their remediation status are tracked in [`docs/compliance/vulnerability-poam.md`](docs/compliance/vulnerability-poam.md).

## Bottom line

Pilot: synthetic data, locked-down box, learn whether CaseLight fits — low risk, high signal. Real data
is a deliberate, separate gate with the controls above in place and a signed risk acceptance. Keep those
two phases clearly apart.
