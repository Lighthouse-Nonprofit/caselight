#!/usr/bin/env node
// bs5_pixeldiff.js — per-surface screenshot drift gate for the POAM-017g polish rungs.
//
// Compares two bs5_sweep evidence dirs (same filenames) with pixelmatch. A polish PR is
// allowed to move the surfaces it deliberately touches (--allow); every OTHER surface
// drifting past the threshold fails the gate. Only meaningful once both runs are on the
// same framework (i.e. after the Q1 BS5 re-baseline — a BS3-vs-BS5 compare flags all 30
// surfaces by design).
//
//   node qa/playwright/bs5_pixeldiff.js --baseline <dir> --candidate <dir> \
//     [--threshold 1.0] [--allow login,dashboard] [--out <dir>]
//
// - threshold: max % of differing pixels per untouched surface (default 1.0).
// - allow: comma-separated surface names (filename minus .png) exempt from the threshold;
//   they are still measured and reported.
// - out: where to write diff PNGs for flagged surfaces (default: <candidate>/pixeldiff).
// - Height drift beyond 2% is itself a flag (content appeared/vanished/moved), since the
//   pixel compare pads the shorter image and would understate reflow.
//
// deps: pixelmatch + pngjs (qa/playwright/package.json; npm install in qa/playwright).

const fs = require('fs');
const path = require('path');
const { PNG } = require('pngjs');
const pixelmatch = require('pixelmatch');

function arg(name, dflt) {
  const i = process.argv.indexOf('--' + name);
  return i > -1 ? process.argv[i + 1] : dflt;
}

const baselineDir = arg('baseline');
const candidateDir = arg('candidate');
if (!baselineDir || !candidateDir) {
  console.error('usage: bs5_pixeldiff.js --baseline <dir> --candidate <dir> [--threshold 1.0] [--allow a,b] [--out <dir>]');
  process.exit(2);
}
const threshold = parseFloat(arg('threshold', '1.0'));
const allow = new Set((arg('allow', '') || '').split(',').map(s => s.trim()).filter(Boolean));
const outDir = arg('out', path.join(candidateDir, 'pixeldiff'));

function pad(png, width, height) {
  if (png.width === width && png.height === height) return png;
  const out = new PNG({ width, height, fill: true });
  // white fill so padding vs page background (white) doesn't inflate the diff
  out.data.fill(255);
  PNG.bitblt(png, out, 0, 0, png.width, png.height, 0, 0);
  return out;
}

const files = fs.readdirSync(baselineDir).filter(f => f.endsWith('.png')).sort();
if (!files.length) { console.error('no PNGs in baseline dir'); process.exit(2); }
fs.mkdirSync(outDir, { recursive: true });

let failures = 0;
const rows = [];
for (const f of files) {
  const name = f.replace(/\.png$/, '');
  const candPath = path.join(candidateDir, f);
  if (!fs.existsSync(candPath)) {
    rows.push([name, 'MISSING', allow.has(name) ? 'allowed' : 'FAIL']);
    if (!allow.has(name)) failures++;
    continue;
  }
  const a = PNG.sync.read(fs.readFileSync(path.join(baselineDir, f)));
  const b = PNG.sync.read(fs.readFileSync(candPath));
  const width = Math.max(a.width, b.width);
  const height = Math.max(a.height, b.height);
  const heightDrift = Math.abs(a.height - b.height) / Math.max(a.height, 1) * 100;
  const pa = pad(a, width, height);
  const pb = pad(b, width, height);
  const diff = new PNG({ width, height });
  const differing = pixelmatch(pa.data, pb.data, diff.data, width, height, { threshold: 0.1 });
  const pct = differing / (width * height) * 100;
  const flagged = pct > threshold || heightDrift > 2;
  const verdict = !flagged ? 'ok' : (allow.has(name) ? 'allowed' : 'FAIL');
  if (verdict === 'FAIL') failures++;
  if (flagged) fs.writeFileSync(path.join(outDir, name + '.diff.png'), PNG.sync.write(diff));
  rows.push([name, pct.toFixed(2) + '%' + (heightDrift > 2 ? ` (height ${heightDrift.toFixed(1)}%)` : ''), verdict]);
}

const w = Math.max(...rows.map(r => r[0].length));
for (const [name, pct, verdict] of rows) {
  console.log(name.padEnd(w + 2) + pct.padEnd(22) + verdict);
}
console.log(`\n${rows.length} surfaces; threshold ${threshold}%; ${failures} FAIL; diffs in ${outDir}`);
process.exit(failures ? 1 : 0);
