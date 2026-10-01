import { writeFileSync, mkdirSync } from 'node:fs';
import { createRequire } from 'node:module';
import { fileURLToPath } from 'node:url';
import path from 'node:path';

const dir = path.dirname(fileURLToPath(import.meta.url));
const TL = createRequire(import.meta.url)('./timeline.js');
const out = path.join(dir, 'out');
const variantIdx = process.argv.indexOf('--variant');
const variant = variantIdx >= 0 ? process.argv[variantIdx + 1] : 'dark';
TL.useVariant(variant);
const suffix = variant === 'dark' ? '' : '-' + variant;
mkdirSync(out, { recursive: true });

const SR = 48000;
const DUR = TL.duration;
const N = Math.ceil(DUR * SR);
const BEAT = 60 / TL.bpm;
const GROOVE_START = TL.phoneIn;
const GROOVE_END = TL.end.start;

const L = new Float32Array(N), R = new Float32Array(N);
const sendL = new Float32Array(N), sendR = new Float32Array(N);
const duck = new Float32Array(N).fill(1);

const hz = m => 440 * Math.pow(2, (m - 69) / 12);
const lpA = fc => 1 - Math.exp(-2 * Math.PI * fc / SR);
let seed = 1;
const noise = () => { seed = (seed * 1664525 + 1013904223) >>> 0; return seed / 2147483648 - 1; };

function biquad(type, f, q) {
  const w = 2 * Math.PI * f / SR, c = Math.cos(w), al = Math.sin(w) / (2 * q);
  let b0, b1, b2;
  if (type === 'bp') { b0 = al; b1 = 0; b2 = -al; }
  else if (type === 'hp') { b0 = (1 + c) / 2; b1 = -(1 + c); b2 = (1 + c) / 2; }
  else { b0 = (1 - c) / 2; b1 = 1 - c; b2 = (1 - c) / 2; }
  const a0 = 1 + al, a1 = -2 * c, a2 = 1 - al;
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0;
  return x => { const y = (b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2) / a0; x2 = x1; x1 = x; y2 = y1; y1 = y; return y; };
}

function add(i, l, r, send = 0) {
  if (i < 0 || i >= N) return;
  L[i] += l; R[i] += r;
  if (send) { sendL[i] += l * send; sendR[i] += r * send; }
}

function kick(t0, gain = 1, deep = false) {
  const len = deep ? 1.2 : 0.38;
  let ph = 0;
  for (let k = 0; k < len * SR; k++) {
    const t = k / SR;
    const f = deep ? 32 + 70 * Math.exp(-t * 18) : 46 + 110 * Math.exp(-t * 35);
    ph += 2 * Math.PI * f / SR;
    const env = Math.exp(-t * (deep ? 3.2 : 9)) * (t < 0.002 ? t / 0.002 : 1);
    const click = t < 0.004 ? noise() * 0.25 * (1 - t / 0.004) : 0;
    const v = (Math.sin(ph) * env + click) * gain * 0.9;
    add(Math.round((t0 + t) * SR), v, v, deep ? 0.25 : 0);
  }
  const s = Math.round(t0 * SR);
  for (let k = 0; k < 0.3 * SR; k++) if (s + k < N) duck[s + k] = Math.min(duck[s + k], 1 - 0.65 * Math.exp(-k / SR * 11));
}

function clap(t0, gain = 1) {
  const bp = biquad('bp', 1500, 0.9);
  for (let k = 0; k < 0.25 * SR; k++) {
    const t = k / SR;
    const bursts = [0, 0.011, 0.022].reduce((a, o) => a + (t >= o ? Math.exp(-(t - o) * (o === 0.022 ? 18 : 90)) : 0), 0);
    const v = bp(noise()) * bursts * gain * 0.55;
    add(Math.round((t0 + t) * SR), v * 0.9, v, 0.35);
  }
}

function hat(t0, gain = 1, open = false) {
  const hp = biquad('hp', 7000, 0.7);
  const dec = open ? 12 : 45;
  for (let k = 0; k < (open ? 0.2 : 0.06) * SR; k++) {
    const t = k / SR;
    const v = hp(noise()) * Math.exp(-t * dec) * gain * 0.22;
    add(Math.round((t0 + t) * SR), v * 0.8, v, 0.1);
  }
}

function saw(ph) { return 2 * (ph - Math.floor(ph + 0.5)); }

function bassNote(t0, len, midi, gain = 1) {
  const f = hz(midi);
  let ph = 0, ph2 = 0.3, y = 0;
  for (let k = 0; k < len * SR; k++) {
    const t = k / SR;
    ph += f / SR; ph2 += f * 1.004 / SR;
    const cut = 260 + 900 * Math.exp(-t * 14);
    y += lpA(cut) * ((saw(ph) + saw(ph2)) * 0.5 - y);
    const env = Math.min(1, t / 0.005) * Math.min(1, (len - t) / 0.03);
    const i = Math.round((t0 + t) * SR);
    const v = (y * 0.8 + Math.sin(2 * Math.PI * f * t) * 0.5) * env * gain * 0.42 * (i < N ? duck[i] : 1);
    add(i, v, v);
  }
}

function padChord(t0, len, notes, gain = 1, bright = 1) {
  for (const [ni, m] of notes.entries()) {
    for (const det of [-0.08, 0.08]) {
      const f = hz(m + det);
      let ph = (ni * 0.37 + (det < 0 ? 0 : 0.5)) % 1, y = 0;
      const pan = det < 0 ? 0.3 : 0.7;
      for (let k = 0; k < len * SR; k++) {
        const t = k / SR;
        ph += f / SR;
        y += lpA(900 * bright + 300 * Math.sin(t * 2.1 + ni)) * (saw(ph) - y);
        const env = Math.min(1, t / 0.25) * Math.min(1, (len - t) / 0.35);
        const i = Math.round((t0 + t) * SR);
        const v = y * env * gain * 0.045 * (i < N ? 0.45 + 0.55 * duck[i] : 1);
        add(i, v * (1 - pan) * 2, v * pan * 2, 0.5);
      }
    }
  }
}

function pluck(t0, midi, gain = 1, pan = 0.5) {
  const f = hz(midi);
  let ph = 0, y = 0;
  for (let k = 0; k < 0.5 * SR; k++) {
    const t = k / SR;
    ph += f / SR;
    const sq = ph % 1 < 0.5 ? 1 : -1;
    y += lpA(600 + 4200 * Math.exp(-t * 20)) * (sq * 0.6 + Math.sin(2 * Math.PI * ph) * 0.4 - y);
    const v = y * Math.exp(-t * 9) * Math.min(1, t / 0.002) * gain * 0.16;
    add(Math.round((t0 + t) * SR), v * (1 - pan) * 2, v * pan * 2, 0.45);
  }
}

function whoosh(tEnd, len = 0.5, gain = 1) {
  let lp = 0, lp2 = 0;
  const t0 = tEnd - len;
  for (let k = 0; k < (len + 0.12) * SR; k++) {
    const t = k / SR;
    const x = Math.min(1, t / len);
    const fc = 300 + 7000 * x * x;
    const n = noise();
    lp += lpA(fc) * (n - lp);
    lp2 += lpA(fc * 0.35) * (n - lp2);
    const env = t < len ? Math.pow(x, 2.2) : Math.exp(-(t - len) * 40);
    const v = (lp - lp2) * env * gain * 0.5;
    const pan = 0.5 + 0.35 * Math.sin(x * Math.PI * 1.5);
    add(Math.round((t0 + t) * SR), v * (1 - pan) * 2, v * pan * 2, 0.3);
  }
}

function click(t0, gain = 1) {
  for (let k = 0; k < 0.03 * SR; k++) {
    const t = k / SR;
    const v = (Math.sin(2 * Math.PI * 2400 * t) * 0.6 + noise() * 0.4) * Math.exp(-t * 260) * gain * 0.35;
    add(Math.round((t0 + t) * SR), v, v, 0.15);
  }
}

function pop(t0, gain = 1, high = false) {
  let ph = 0;
  for (let k = 0; k < 0.16 * SR; k++) {
    const t = k / SR;
    const f = (high ? 900 : 620) * (1 + 0.6 * Math.min(1, t / 0.05));
    ph += 2 * Math.PI * f / SR;
    const v = Math.sin(ph) * Math.exp(-t * 28) * Math.min(1, t / 0.003) * gain * 0.22;
    add(Math.round((t0 + t) * SR), v, v, 0.5);
  }
}

function riser(t0, len, gain = 1) {
  const bp = biquad('bp', 2000, 1.2);
  let ph = 0;
  for (let k = 0; k < len * SR; k++) {
    const t = k / SR, x = t / len;
    ph += 2 * Math.PI * (220 + 660 * x * x) / SR;
    const v = (bp(noise()) * 0.6 + Math.sin(ph) * 0.15) * Math.pow(x, 2.5) * gain * 0.4;
    add(Math.round((t0 + t) * SR), v, v, 0.5);
  }
}

const CHORDS = [
  { root: 45, pad: [57, 60, 64, 71] },
  { root: 41, pad: [57, 60, 65, 69] },
  { root: 48, pad: [55, 60, 64, 67] },
  { root: 43, pad: [55, 59, 62, 67] },
];

const hits = [];

[69, 72, 76, 81].forEach((m, i) => { const t = TL.intro.lines[i].at; pluck(t, m, 2.4, 0.5); pluck(t, m - 12, 1.4, 0.5); hits.push({ t, kind: 'word' }); });
riser(0.9, GROOVE_START - 0.9, 1);
kick(GROOVE_START, 1.2, true);
hits.push({ t: GROOVE_START, kind: 'drop' });

const beats = [], downbeats = [];
for (let b = 0; GROOVE_START + b * BEAT < GROOVE_END - 1e-6; b++) {
  const t = GROOVE_START + b * BEAT;
  beats.push(+t.toFixed(3));
  const inBar = b % 4;
  if (inBar === 0) downbeats.push(+t.toFixed(3));
  if (b > 0) kick(t, inBar === 0 ? 1 : 0.9);
  if (t >= 5.0 && (inBar === 1 || inBar === 3)) clap(t, 1);
  hat(t + BEAT / 2, 1, inBar === 3 && t >= 8);
  if (t >= 10.0) { hat(t + BEAT / 4, 0.45); hat(t + 3 * BEAT / 4, 0.45); }
}
for (let k = 0; k < 4; k++) clap(GROOVE_END - BEAT + k * BEAT / 4, 0.5 + k * 0.15);

for (let bar = 0; GROOVE_START + bar * 2 * BEAT * 2 < GROOVE_END; bar++) {
  const t0 = GROOVE_START + bar * 4 * BEAT;
  const ch = CHORDS[bar % 4];
  const len = Math.min(4 * BEAT, GROOVE_END - t0);
  padChord(t0, len + 0.3, ch.pad, 1, (TL.flip ? (TL.flip.from === 'light') !== (t0 >= TL.flip.at) : t0 >= 21.5) ? 1.6 : 1);
  const pattern = [0, 0, 12, 0, 0, 12, 0, 7];
  for (let e = 0; e < 8; e++) {
    const tn = t0 + e * BEAT / 2;
    if (tn >= GROOVE_END) break;
    bassNote(tn, BEAT / 2 - 0.02, ch.root + pattern[e], 1);
  }
  if (t0 >= 8.0) {
    const step = t0 >= 16.5 ? BEAT / 4 : BEAT / 2;
    const tones = [...ch.pad, ch.pad[1] + 12, ch.pad[2] + 12];
    for (let k = 0, tn = t0; tn < Math.min(t0 + 4 * BEAT, GROOVE_END); k++, tn += step) {
      pluck(tn, tones[(k * 3) % tones.length] + 12, 0.35, k % 2 ? 0.3 : 0.7);
    }
  }
}

for (const s of TL.sections.slice(1)) { whoosh(s.start, 0.5, 1); hits.push({ t: s.start, kind: 'section' }); }
whoosh(TL.phoneOut + 0.15, 0.6, 1.1);
if (TL.flip) {
  riser(TL.flip.at - 0.9, 0.9, 0.7);
  [76, 81, 84, 88].forEach((m, i) => pluck(TL.flip.at + i * 0.06, m, 0.8, i % 2 ? 0.3 : 0.7));
  hits.push({ t: TL.flip.at, kind: 'flip' });
}
for (const tp of TL.taps) { const t = TL.outTime(tp.src, tp.dir); click(t, 1); hits.push({ t: +t.toFixed(3), kind: 'tap' }); }
for (const l of TL.lifts) { pop(l.start + 0.02, 1, !!l.ai); hits.push({ t: l.start, kind: 'lift' }); }

riser(GROOVE_END, TL.end.logo - GROOVE_END, 0.8);
kick(TL.end.logo, 1.3, true);
hits.push({ t: TL.end.logo, kind: 'logo' });
padChord(TL.end.logo, DUR - TL.end.logo, [57, 64, 69, 71, 76], 1.6, 1.4);
[81, 76, 72, 69].forEach((m, i) => pluck(TL.end.logo + 0.22 + i * 0.25, m, 0.7, 0.5));

function reverb(inL, inR) {
  const combs = [1557, 1617, 1491, 1422, 1277, 1356].map(d => Math.round(d * SR / 44100));
  const aps = [225, 556, 441].map(d => Math.round(d * SR / 44100));
  const run = (x, spread) => {
    const y = new Float32Array(N);
    for (const d0 of combs) {
      const d = d0 + spread, buf = new Float32Array(d);
      let idx = 0, lp = 0;
      for (let i = 0; i < N; i++) {
        const o = buf[idx];
        lp += 0.35 * (o - lp);
        buf[idx] = x[i] + lp * 0.84;
        idx = (idx + 1) % d;
        y[i] += o / combs.length;
      }
    }
    for (const d0 of aps) {
      const d = d0 + spread, buf = new Float32Array(d);
      let idx = 0;
      for (let i = 0; i < N; i++) {
        const b = buf[idx], v = -y[i] + b;
        buf[idx] = y[i] + b * 0.5;
        idx = (idx + 1) % d;
        y[i] = v;
      }
    }
    return y;
  };
  return [run(inL, 0), run(inR, 23)];
}

const [rvL, rvR] = reverb(sendL, sendR);
let peak = 0;
for (let i = 0; i < N; i++) {
  const t = i / SR;
  const fade = Math.min(1, (DUR - t) / 0.8);
  L[i] = Math.tanh((L[i] + rvL[i] * 0.55) * 1.1) * fade;
  R[i] = Math.tanh((R[i] + rvR[i] * 0.55) * 1.1) * fade;
  peak = Math.max(peak, Math.abs(L[i]), Math.abs(R[i]));
}
const norm = 0.89 / peak;

const buf = Buffer.alloc(44 + N * 4);
buf.write('RIFF', 0); buf.writeUInt32LE(36 + N * 4, 4); buf.write('WAVE', 8);
buf.write('fmt ', 12); buf.writeUInt32LE(16, 16); buf.writeUInt16LE(1, 20); buf.writeUInt16LE(2, 22);
buf.writeUInt32LE(SR, 24); buf.writeUInt32LE(SR * 4, 28); buf.writeUInt16LE(4, 32); buf.writeUInt16LE(16, 34);
buf.write('data', 36); buf.writeUInt32LE(N * 4, 40);
for (let i = 0; i < N; i++) {
  buf.writeInt16LE(Math.round(L[i] * norm * 32767), 44 + i * 4);
  buf.writeInt16LE(Math.round(R[i] * norm * 32767), 46 + i * 4);
}
writeFileSync(path.join(out, `music${suffix}.wav`), buf);
writeFileSync(path.join(out, `beats${suffix}.json`), JSON.stringify({ bpm: TL.bpm, beats, downbeats, hits: hits.sort((a, b) => a.t - b.t) }, null, 2));
console.log(`music${suffix}.wav ${DUR}s · ${beats.length} beats · ${hits.length} hits`);
