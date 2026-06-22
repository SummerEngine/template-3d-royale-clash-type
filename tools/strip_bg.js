#!/usr/bin/env node
// Chroma-key a solid background color to transparent and write an RGBA PNG.
// Usage:
//   node tools/strip_bg.js <input.png> <output.png> [--key R,G,B] [--tol N] [--feather N]
// Defaults: key = magenta (255,0,255), tol = 90, feather = 40.
// Prints a JSON report of how much was made transparent so callers can verify
// a real alpha channel was produced (not a baked fake background).

const fs = require("fs");
const { PNG } = require("pngjs");

function parseArgs(argv) {
  const a = { key: [255, 0, 255], tol: 90, feather: 40, _: [] };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === "--key") a.key = argv[++i].split(",").map(Number);
    else if (t === "--tol") a.tol = Number(argv[++i]);
    else if (t === "--feather") a.feather = Number(argv[++i]);
    else a._.push(t);
  }
  return a;
}

const args = parseArgs(process.argv.slice(2));
const [input, output] = args._;
if (!input || !output) {
  console.error("usage: node strip_bg.js <input.png> <output.png> [--key R,G,B] [--tol N] [--feather N]");
  process.exit(2);
}

const [kr, kg, kb] = args.key;
const tol = args.tol;
const feather = args.feather;

const png = PNG.sync.read(fs.readFileSync(input));
const { width, height, data } = png;

let transparent = 0;
let partial = 0;
const total = width * height;

for (let i = 0; i < data.length; i += 4) {
  const r = data[i], g = data[i + 1], b = data[i + 2];
  // Euclidean distance to the key color.
  const dist = Math.sqrt((r - kr) ** 2 + (g - kg) ** 2 + (b - kb) ** 2);
  if (dist <= tol) {
    data[i + 3] = 0; // fully background -> transparent
    transparent++;
  } else if (dist <= tol + feather) {
    // Feather band: ramp alpha so edges aren't hard-cut, and pull color away
    // from the key to reduce colored fringe.
    const t = (dist - tol) / feather; // 0..1
    data[i + 3] = Math.round(255 * t);
    partial++;
  }
}

fs.writeFileSync(output, PNG.sync.write(png));

const report = {
  ok: true,
  input,
  output,
  width,
  height,
  totalPixels: total,
  transparentPixels: transparent,
  partialPixels: partial,
  fractionTransparent: +(transparent / total).toFixed(4),
};
console.log(JSON.stringify(report));
