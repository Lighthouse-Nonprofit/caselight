# Post-incident record — Tier-4 name-column data loss on the pilot box

| | |
|---|---|
| **Date** | 2026-07-22 (detected & recovered same day; second regression found and fixed 2026-07-23) |
| **System** | Pilot EC2 box, tenant `cases` |
| **Data impact** | All 4 encrypted client-name columns NULLed for 27 client rows — **synthetic demo data only** (per the pilot's hard rule; no real client data existed) |
| **Availability impact** | None — app stayed up; names rendered blank |
| **Recovery** | 26/26 demo records restored same day from the dev environment's identical dataset (matched by unique client code, fallback slug); 1 box-only smoke-test record has no recoverable name |
| **Fixes** | PR #202 (2026-07-23), PR #203 (2026-07-23) |

## Timeline

1. **2026-07-22** — routine deploy of UX rounds 3+4 (`bootstrap.sh` rerun). The sync updated
   `bootstrap.sh` itself mid-run; bash kept executing the *old* script text, so the deploy ran
   the old stage list: tier encryption backfills, but **not** the new
   `encryption:reencrypt_client_names` stage that release required.
2. The tier-4 backfill ran under the new image, where client names had just migrated to the
   `ignore_case` deterministic scheme. It read each column via `public_send` — the model
   *reader*, which for `ignore_case` columns prefers the `original_*` display sidecar. The
   sidecars were still NULL (that's what the skipped stage would have populated), so the
   backfill read `nil` and `update_columns` wrote **NULL over every name ciphertext**.
3. Post-deploy verification caught blank names; a manual rake run could not help (the stored
   ciphertext was already gone). Names were restored from the dev environment's identical
   synthetic dataset the same day, and verified live (render + case-insensitive search).
4. **2026-07-23** — hotfix PR #202 merged and deployed. Post-deploy verification then caught a
   **second regression**: the redeploy re-ran `reencrypt_client_names` (it runs every deploy),
   which lowercased every display name — on an already-migrated row `read_attribute` returns
   the downcased search column, and the task blindly wrote that into the display sidecar.
5. Hotfix PR #203 merged and deployed; display case re-restored from the dev dataset; a final
   deploy confirmed the task now skips migrated rows (`re-encrypted=0`).

## Root causes

1. **Self-updating deploy script** — a `git reset --hard` mid-run changes `bootstrap.sh` on
   disk, but the running bash process continues executing the old text. Any release whose
   correctness depends on a *new* deploy stage silently loses that stage.
2. **Reader-override read in a write-back loop** — `encrypt_record!` read attributes via
   `public_send`. Rails' `ignore_case` encryption overrides the reader to prefer the
   `original_*` sidecar; reading through the override and writing the result back destroys the
   column whenever the sidecar lags the column.
3. **Non-idempotent migration task** — `reencrypt_client_names`'s read-and-rewrite is only
   correct for legacy rows (old-scheme ciphertext holds the original case). Re-running it on
   migrated rows degraded data (display case), and it runs on every deploy.

## Corrective actions (all shipped)

| Action | Where | PR |
|---|---|---|
| Backfill reads via `read_attribute`, never `public_send` | `lib/tasks/encryption.rake` | #202 |
| NIL-GUARD: a nil read of a non-NULL stored value skips the column and warns — the backfill can no longer write NULL over ciphertext | `encryption.rake` (both tasks) | #202 |
| `bootstrap.sh` self-update guard: re-exec the fresh copy once when the sync changes the script | `bootstrap.sh` (`BOOTSTRAP_REEXEC`) | #202 |
| Reencrypt idempotent **by skipping**: rows with a populated `original_*` sidecar are untouched; clean re-run reports `re-encrypted=0` | `encryption.rake` | #203 |
| Regression specs: incident repro, nil-guard, double-run case preservation, and a drift guard that greps the rake source (the spec's inlined copy of the primitive had faithfully matched the rake *while both were wrong*) | `spec/lib/tasks/encryption_backfill_spec.rb`, `spec/lib/tasks/encryption_reencrypt_names_spec.rb` | #202, #203 |
| Operator guidance: deploy-log `SKIPPING column` = stop and investigate; routine redeploys must show `re-encrypted=0` | `OPERATIONS.md` | docs |

## Lessons

- **Any code path that reads an encrypted attribute in order to write it back must use
  `read_attribute`.** Model readers are overridable and do not reflect the column.
- **Deploy-critical rake tasks run on every deploy** — they must be proven idempotent across
  *two* runs (the second run is where non-idempotence bites), and "idempotent" must be verified
  against exact values (case included), not just non-blank.
- **A deploy script that updates itself needs a re-exec guard** — otherwise the release that
  introduces a new stage is precisely the release that skips it.
- **Post-deploy verification catches what reviews miss** — both regressions were found by
  comparing live data to expected values, not by tests or review. Verification checklists
  should compare exact strings.
- The synthetic-data-only pilot rule turned a data-loss incident into a same-day restore
  exercise. It stays load-bearing until the `SECURITY.md` production gate is met.

*IR-8 review: this record satisfies the incident-response policy's post-incident requirements
(root cause, corrective actions, lessons). Policy reviewed against this incident 2026-07-23 —
the containment and communication steps were adequate; the corrective actions above closed the
gaps that mattered.*
