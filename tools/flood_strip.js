#!/usr/bin/env node
// Remove a solid background by flood-filling from the image edges to transparent,
// leaving interior pixels of the same colour intact (so white shields/teeth/etc.
// inside a sprite survive while the white backdrop is keyed out).
// Usage: node tools/flood_strip.js <in.png> <out.png> [--tol N] [--feather N]
// Defaults: tol = 60 (colour distance from the corner bg colour), feather = 2 px.

const fs = require("fs");
const { PNG } = require("pngjs");

function arg(name, def) {
  const i = process.argv.indexOf(name);
  return i !== -1 ? Number(process.argv[i + 1]) : def;
}
const input = process.argv[2], output = process.argv[3];
if (!input || !output) { console.error("usage: flood_strip.js <in> <out> [--tol N] [--feather N]"); process.exit(2); }
const tol = arg("--tol", 60);
const feather = arg("--feather", 2);

const png = PNG.sync.read(fs.readFileSync(input));
const { width: W, height: H, data } = png;
const idx = (x, y) => (y * W + x) * 4;

// Background reference = average of the 4 corners.
const corners = [[0,0],[W-1,0],[0,H-1],[W-1,H-1]];
let br = 0, bg = 0, bb = 0;
for (const [x,y] of corners) { const i = idx(x,y); br += data[i]; bg += data[i+1]; bb += data[i+2]; }
br/=4; bg/=4; bb/=4;
const near = (i) => Math.sqrt((data[i]-br)**2 + (data[i+1]-bg)**2 + (data[i+2]-bb)**2) <= tol;

// BFS flood from every edge pixel that matches the bg colour.
const isBg = new Uint8Array(W * H);
const q = [];
function seed(x, y) { const p = y*W+x; if (!isBg[p] && near(idx(x,y))) { isBg[p]=1; q.push(p); } }
for (let x=0;x<W;x++){ seed(x,0); seed(x,H-1); }
for (let y=0;y<H;y++){ seed(0,y); seed(W-1,y); }
while (q.length) {
  const p = q.pop(); const x = p % W, y = (p / W) | 0;
  if (x>0) seed(x-1,y);
  if (x<W-1) seed(x+1,y);
  if (y>0) seed(x,y-1);
  if (y<H-1) seed(x,y+1);
}

// Apply: bg pixels -> fully transparent. Then a soft feather: non-bg pixels within
// `feather` px of a bg pixel get reduced alpha for a clean anti-aliased edge.
let cleared = 0;
for (let p=0;p<W*H;p++){ if (isBg[p]) { data[p*4+3]=0; cleared++; } }
if (feather > 0) {
  const src = isBg.slice();
  for (let y=0;y<H;y++) for (let x=0;x<W;x++){
    const p = y*W+x; if (src[p]) continue;
    let dmin = feather+1;
    for (let dy=-feather;dy<=feather;dy++) for (let dx=-feather;dx<=feather;dx++){
      const nx=x+dx, ny=y+dy; if (nx<0||ny<0||nx>=W||ny>=H) continue;
      if (src[ny*W+nx]) { const d=Math.abs(dx)+Math.abs(dy); if (d<dmin) dmin=d; }
    }
    if (dmin<=feather) data[p*4+3] = Math.min(data[p*4+3], Math.round(255*(dmin/(feather+1))));
  }
}
fs.writeFileSync(output, PNG.sync.write(png));
console.log(JSON.stringify({ W, H, bg:[Math.round(br),Math.round(bg),Math.round(bb)], cleared, pct:+(100*cleared/(W*H)).toFixed(1) }));
