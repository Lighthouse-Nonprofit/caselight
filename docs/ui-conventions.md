# UI conventions

Short, binding rules for CaseLight's UI. Started with the destructive-control placement
convention (UX round 3, rung D4 — owner: "switch the exit/remove [red] buttons to the
outside of elements, rather than inward").

## Destructive controls (delete / exit / remove / reject)

1. **Inline action groups** (table Actions cells, card action rows, `.ibox-tools`): the
   destructive control goes **last, at the outer (right) edge**, separated from the routine
   actions with the `.action-gap-start` utility. A red button must never read as the "next"
   button in a row.
2. **Form and modal footers**: the primary action sits at the right edge; a destructive
   action that is *not* the primary is anchored at the **opposite outer edge** (far left),
   never adjacent to Save. (Confirmation modals whose whole purpose is the destructive act —
   Exit From Organization, Close Resettlement Case, break-glass — keep the destructive as
   the right-edge primary.)
3. **Dropdown menus**: Delete stays **last, after a divider** (`%hr.dropdown-divider`),
   styled `text-danger` — the long-standing convention.
4. **Row-level destructives prefer `btn-outline-danger`**; solid `btn-danger` is reserved
   for confirmation-modal primaries.

Existing surfaces already conforming (verified in the D4 audit): task/changelog/entry rows
render edit-then-trash with trash outermost; the hub Actions dropdowns end with
divider + Delete. The D4 change itself fixed the Programs tables, where Exit led the row.

## Section collapse (rung D2)

Collapsible `.ibox` sections use `shared/_ibox_collapse_link` in `.ibox-tools` +
`ibox_classes(collapsed:)` on the `.ibox`. `.collapsed` on the `.ibox` is the single source
of truth; the chevron glyph is CSS-owned — always ship `fa-chevron-up`. Empty sections
should start collapsed (pass the same flag to both helpers).

## Links vs buttons (investor UX round, 2026-07)

One visual vocabulary for "what happens when I click":

1. **Navigations are links.** Harbor color, underline **on hover** (the global
   `#page-wrapper a:hover` rule in `caselight_theme/_root.scss` — exclusion-scoped so
   buttons/nav/chips/cards keep their own treatments). Linked values inside info-grid badges
   pick up the same affordance so they read differently from plain-text badges.
2. **`.btn` chrome is reserved for actions** (submits, state changes, openers). Counts and
   statuses are **badges/chips, never `.btn`** — the family grid's popover totals were the
   offenders (now `.badge.text-bg-info`).
3. **Quiet icon controls** (the ibox collapse chevron) get the `.ibox-collapse-glyph`
   treatment, not button chrome. Always render via `shared/_ibox_collapse_link`.
4. **Grandfathered:** ~60 legacy sites wrap a `.btn`-classed DIV inside a `link_to`. They
   are excluded from the hover-underline rule via `:has()` guards and are NOT to be
   imitated: new code puts the `.btn` classes on the anchor/button element itself.
