# CMIA gap analysis (California Confidentiality of Medical Information Act)

**Status:** working analysis for counsel review — *not legal advice*. Prepared
2026-08-04 when the engagement posture moved from a HIPAA BAA to a **Data
Processing Agreement with a CMIA addendum** for SLO for HOME (California
nonprofit, resettlement flavor, box `slo4home.lighthousent.org`).

Companion docs: `hipaa-gap-analysis` (concluded the org is most likely **not** a
HIPAA covered entity — which is why CMIA, not HIPAA, is the operative regime),
`ssp.md` (control descriptions), `control-matrix.md`, `pii-inventory.md`.

## 1. Why CMIA rather than HIPAA

CMIA (Cal. Civ. Code § 56 et seq.) protects "medical information" —
individually identifiable information about a person's medical history, mental
or physical condition, or treatment. Two features make it bite here where HIPAA
may not:

* It does not depend on the covered-entity/business-associate chain. A
  California organization handling medical information is in scope regardless of
  whether it bills insurance.
* § 56.06 extends "provider of health care" status to businesses that maintain
  medical information on an individual's behalf, and to software offered for
  maintaining that information. Whether **Lighthouse** is itself a provider
  under § 56.06, or a recipient bound by § 56.13 / § 56.245 not to re-disclose,
  is the legal question for counsel. Either way the contractual posture is the
  same: DPA + CMIA flow-down.
* Remedies are real and per-violation (§ 56.36 — nominal statutory damages
  without proof of harm), so breach avoidance is the design driver.

**Medical information CaseLight actually holds** (resettlement flavor): the
`Health (Family)` and `Member: Health` custom forms, the `Mental Health &
Well-Being` (4B) and `Physical Health & Healthcare Access` (4A) assessment
domains, health-related case notes and progress notes, and benefits data
(Medi-Cal enrollment) that reveals health-program participation. The youth
flavor additionally holds safety plans, victim-services records, and SOGI.

## 2. AB 352 (2023, effective 2024-07-01) — the specific technical duty

AB 352 amended CMIA to impose obligations on any business that electronically
stores or maintains medical information **related to gender-affirming care,
abortion and abortion-related services, or contraception**. In substance the
system must be able to:

1. **Limit user access** to that category of information;
2. **Segregate** it from the rest of the record; and
3. **Prevent its disclosure or sharing with out-of-state persons or entities**,
   and decline out-of-state requests absent a California-permitted basis.

### Mapping to CaseLight controls

| AB 352 duty | Current control | Verdict |
|---|---|---|
| Limit user access | Phase-5 sensitivity tiers (`standard` / `restricted` / `emergency_only`) on CustomField **and** Domain, enforced by `SensitivityPolicy`; `emergency_only` is unlockable only via audited break-glass and **never** for a strategic overviewer | **Met** — put the category in a dedicated `emergency_only` form |
| Segregate from the rest of the record | Each custom form is its own record (`CustomFieldProperty`), non-deterministically encrypted at rest, and the record-less visible set keeps hidden forms off the Overview; reports respect `visible_custom_field_ids` (proven by the Stop-the-Hate bias-table gating, which renders "restricted section hidden" rather than zeros, in HTML **and** CSV **and** PDF) | **Met in mechanism**, but no form exists yet — see gap G2 |
| Prevent out-of-state disclosure | Organizational, plus data residency — see gap **G1** | **Gap** |

## 3. Gaps and recommendations

**G1 — Data residency is out-of-state (highest priority, cheapest to fix now).**
The production box runs in **AWS us-east-2 (Ohio)**; backups (vault `caselight`)
are in the same region. AB 352 addresses *disclosure* to out-of-state persons or
entities rather than storage location, and AWS acts as a processor under contract
rather than a requesting party — but storing a California nonprofit's medical
information physically outside California is an avoidable talking point in a
CMIA addendum negotiation, and it weakens the "we cannot disclose out of state"
narrative.
*Recommendation:* if counsel wants California residency, **relocate now**. The
box holds zero client records, so a rebuild in **us-west-1 (N. California)** is
about an hour (provision, bootstrap, re-point one DNS record, re-create the
backup plan) versus a data-migration project later. Cost delta is roughly
10–15% on the instance.

**G2 — No dedicated confidential-health form.** The mechanism exists but nothing
uses it. *Recommendation:* seed a `Confidential Health Information` client form
at `emergency_only` for the AB 352 category, and instruct staff (admin guide)
that gender-affirming-care / reproductive-health notes belong there and not in
general case notes. Small seed change; no code required.

**G3 — Out-of-state disclosure and subpoena-response procedure.** The policy
pack has no CMIA-specific instruction on refusing out-of-state requests.
*Recommendation:* add a short procedure to `docs/compliance/policies` — who
receives a request, the requirement to obtain California-permitted basis before
any release, and the audit-log entry to create. Organizational, not code.

**G4 — Breach-notification trigger.** Incident response covers audit-log
review, but not the CMIA / Cal. Civ. Code § 1798.82 notification clock.
*Recommendation:* add a CMIA trigger and timeline to the incident-response
policy.

**G5 — Minors' confidential services (youth box).** California minors 12+ may
consent to certain care, and that information is confidential from parents. The
youth flavor's sensitivity tiers already support note-level confidentiality;
flag for the youth DPA rather than this one.

## 4. Controls already in place that the DPA can cite

Drawn from `ssp.md` / `control-matrix.md`, all verified in production:

* **Encryption in transit** — TLS 1.2+ via Caddy with automatic certificate
  management; HSTS; HTTP redirects to HTTPS.
* **Encryption at rest** — encrypted EBS volume **plus** application-level field
  encryption: non-deterministic for narrative/medical fields, deterministic only
  where lookup requires it. Keys are explicit env values held off-box, so a
  stolen database dump is ciphertext-locked (proven in the 2026-08-04 restore
  drill).
* **Access control** — role-based (8 roles), caseload-scoped record access,
  field-level sensitivity tiers, audited break-glass, MFA with passkey support,
  automatic disabling of inactive accounts, access reviews.
* **Audit** — append-only access logs, change history in a separate store,
  values-free logging (audit entries never carry field values), 90-day online
  retention with verified archive.
* **Tenant isolation** — schema-per-organization with a request-level boundary
  tripwire; one flavor per server.
* **Data lifecycle** — retention and purge jobs, subject-access export, upload
  authorization.
* **Backup and recovery** — daily whole-volume snapshots (35-day retention) plus
  nightly logical dumps (14-day local rotation); documented recovery unit
  (dump + keys) and a completed restore drill.
* **Vulnerability management** — CI secret scanning, SAST, dependency CVE gates;
  a POA&M ledger with owners and dates.

## 5. What changes in our documents

* `docs/PRODUCTION-RESETTLEMENT.md` go-live gate: **DPA + CMIA addendum** signed
  (replacing "BAA"). Accepting the AWS Business Associate Addendum in AWS
  Artifact becomes **optional** — harmless and it adds AWS security commitments,
  but it is not required outside a HIPAA chain, and it constrains you to
  HIPAA-eligible services.
* `SECURITY.md`: the real-data gate should reference the CMIA addendum and G2's
  confidential-health form.
