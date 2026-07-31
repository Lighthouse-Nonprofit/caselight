// D5: the preview page is server-rendered now (real shared/fields partials) — no builder
// stage to initialize. The module stays registered so the dispatcher lookup is a no-op.
CIF.Custom_fieldsShow = CIF.Custom_fieldsPreview = {
  init() {},
};
