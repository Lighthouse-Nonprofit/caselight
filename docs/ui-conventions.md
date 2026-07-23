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
