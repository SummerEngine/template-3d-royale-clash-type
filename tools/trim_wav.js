#!/usr/bin/env node
// Trim a WAV to N milliseconds (with a short fade-out so the cut doesn't click),
// optionally apply a gain, and rewrite as 16-bit PCM mono (what Godot imports
// cleanly). Decodes common source formats (PCM 8/16/24/32, float32).
// Usage:
//   node tools/trim_wav.js <in.wav> [out.wav] [--ms 200] [--gain 1.0]
// out.wav defaults to in-place (overwrites input). Reads fully before writing.

const fs = require("fs");

function parseArgs(argv) {
  const a = { ms: 200, gain: 1.0, _: [] };
  for (let i = 0; i < argv.length; i++) {
    const t = argv[i];
    if (t === "--ms") a.ms = Number(argv[++i]);
    else if (t === "--gain") a.gain = Number(argv[++i]);
    else a._.push(t);
  }
  return a;
}

const args = parseArgs(process.argv.slice(2));
const input = args._[0];
const output = args._[1] || input;
if (!input) {
  console.error("usage: node trim_wav.js <in.wav> [out.wav] [--ms 200] [--gain 1.0]");
  process.exit(2);
}

const buf = fs.readFileSync(input);
if (buf.toString("ascii", 0, 4) !== "RIFF" || buf.toString("ascii", 8, 12) !== "WAVE") {
  console.error("not a RIFF/WAVE file: " + input);
  process.exit(1);
}

let pos = 12, fmt = null, dataOff = -1, dataLen = 0;
while (pos + 8 <= buf.length) {
  const id = buf.toString("ascii", pos, pos + 4);
  const sz = buf.readUInt32LE(pos + 4);
  const body = pos + 8;
  if (id === "fmt ") {
    fmt = {
      audioFormat: buf.readUInt16LE(body),
      channels: buf.readUInt16LE(body + 2),
      sampleRate: buf.readUInt32LE(body + 4),
      bitsPerSample: buf.readUInt16LE(body + 14),
    };
  } else if (id === "data") {
    dataOff = body;
    dataLen = Math.min(sz, buf.length - body);
  }
  pos = body + sz + (sz & 1);
}
if (!fmt || dataOff < 0) {
  console.error("missing fmt/data chunk: " + input);
  process.exit(1);
}

const { audioFormat, channels, sampleRate, bitsPerSample } = fmt;
const bytesPer = bitsPerSample / 8;
const frameBytes = bytesPer * channels;
const totalFrames = Math.floor(dataLen / frameBytes);

function readSample(off) {
  if (audioFormat === 3 && bitsPerSample === 32) return buf.readFloatLE(off);
  if (audioFormat === 1) {
    if (bitsPerSample === 16) return buf.readInt16LE(off) / 32768;
    if (bitsPerSample === 8) return (buf.readUInt8(off) - 128) / 128;
    if (bitsPerSample === 24) {
      const v = buf.readUInt8(off) | (buf.readUInt8(off + 1) << 8) | (buf.readUInt8(off + 2) << 16);
      const s = v & 0x800000 ? v - 0x1000000 : v;
      return s / 8388608;
    }
    if (bitsPerSample === 32) return buf.readInt32LE(off) / 2147483648;
  }
  return 0;
}

const keepFrames = Math.min(Math.round((sampleRate * args.ms) / 1000), totalFrames);
const fadeFrames = Math.min(Math.round(sampleRate * 0.012), keepFrames);
const out = Buffer.alloc(keepFrames * 2); // 16-bit mono
for (let f = 0; f < keepFrames; f++) {
  let acc = 0;
  for (let c = 0; c < channels; c++) acc += readSample(dataOff + (f * channels + c) * bytesPer);
  let s = (acc / channels) * args.gain;
  const fadePos = f - (keepFrames - fadeFrames);
  if (fadePos > 0) s *= (keepFrames - f) / fadeFrames;
  s = Math.max(-1, Math.min(1, s));
  out.writeInt16LE(Math.round(s * 32767), f * 2);
}

const header = Buffer.alloc(44);
header.write("RIFF", 0);
header.writeUInt32LE(36 + out.length, 4);
header.write("WAVE", 8);
header.write("fmt ", 12);
header.writeUInt32LE(16, 16);
header.writeUInt16LE(1, 20); // PCM
header.writeUInt16LE(1, 22); // mono
header.writeUInt32LE(sampleRate, 24);
header.writeUInt32LE(sampleRate * 2, 28);
header.writeUInt16LE(2, 32); // block align
header.writeUInt16LE(16, 34); // bits
header.write("data", 36);
header.writeUInt32LE(out.length, 40);
fs.writeFileSync(output, Buffer.concat([header, out]));

console.log(JSON.stringify({
  output,
  inMs: Math.round((totalFrames / sampleRate) * 1000),
  outMs: Math.round((keepFrames / sampleRate) * 1000),
  inFormat: (audioFormat === 3 ? "float" : "pcm") + bitsPerSample + "x" + channels,
  gain: args.gain,
}));
