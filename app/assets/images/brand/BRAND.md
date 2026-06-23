# CaseLight — brand assets

Marks for the CaseLight repo and website. Wordmark type is **Space Grotesk** (600);
monospace accents are **JetBrains Mono**.

## Colors
| Token | Hex |
|---|---|
| Harbor navy | `#102A3C` |
| First-light amber | `#F2A23C` (use `#F8B85C` on dark backgrounds) |
| Sea-foam cream | `#F3EEE4` |

## Files

### logo/  — full wordmark (transparent PNG, 2184×909)
- `caselight-logo.png` — navy wordmark, for light backgrounds
- `caselight-logo-ondark.png` — cream wordmark, for dark backgrounds

GitHub README (auto light/dark):
```html
<picture>
  <source media="(prefers-color-scheme: dark)" srcset="caselight-logo-ondark.png">
  <img alt="CaseLight" src="caselight-logo.png" width="420">
</picture>
```

### icon/  — square mark
- `caselight-icon.svg` — app icon, navy background (scalable master)
- `caselight-icon-1024.png` / `-512.png` / `-192.png`
- `caselight-mark.svg` / `caselight-mark.png` — lighthouse only, transparent (navy, for light bg)
- `caselight-mark-ondark.svg` / `caselight-mark-ondark.png` — lighthouse only, transparent (cream, for dark bg)

Use `caselight-icon-512.png` (or larger) as the **GitHub org/repo avatar**.

### favicon/  — website
- `favicon.svg` — modern browsers (scalable)
- `favicon-32.png`, `favicon-16.png`, `favicon-48.png`
- `apple-touch-icon-180.png`

```html
<link rel="icon" href="/favicon.svg" type="image/svg+xml">
<link rel="icon" href="/favicon-32.png" sizes="32x32">
<link rel="apple-touch-icon" href="/apple-touch-icon-180.png">
```
(Need a legacy `favicon.ico`? Convert `favicon-32.png` with any ICO tool.)

### social/
- `github-social-preview.png` — 2560×1280. Upload under **repo → Settings → Social preview**.

## Notes
The wordmark PNGs are rendered from live Space Grotesk at high resolution and scale down
cleanly. For a vector wordmark with outlined text, ask and I can produce one.
