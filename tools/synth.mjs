// Offline renderer for every sound in the game: a sample-level port of the web build's
// WebAudio synth (same oscillators, filters, envelopes and music patterns).
// node tools/synth.mjs  ->  assets/audio/*.wav
import { mkdirSync, writeFileSync } from 'node:fs';

const SR = 32000;
const OUT = new URL('../assets/audio/', import.meta.url).pathname;
mkdirSync(OUT, { recursive: true });

// ---------------------------------------------------------------- primitives
let seed = 1234567;
const rnd = () => {
  seed = (seed + 0x6d2b79f5) >>> 0;
  let t = seed;
  t = Math.imul(t ^ (t >>> 15), t | 1);
  t ^= t + Math.imul(t ^ (t >>> 7), t | 61);
  return ((t ^ (t >>> 14)) >>> 0) / 4294967296;
};
const noise = () => rnd() * 2 - 1;
const midi = (m) => 440 * Math.pow(2, (m - 69) / 12);
const buf = (sec) => new Float32Array(Math.ceil(sec * SR));

function polyblep(t, dt) {
  if (t < dt) {
    t /= dt;
    return t + t - t * t - 1;
  }
  if (t > 1 - dt) {
    t = (t - 1) / dt;
    return t * t + t + t + 1;
  }
  return 0;
}

/** Stateful oscillator with optional exponential frequency ramp. */
function oscillator(type, f0, f1 = f0, rampT = 0, detuneCents = 0) {
  let ph = 0;
  let n = 0;
  const det = Math.pow(2, detuneCents / 1200);
  return () => {
    const t = n / SR;
    const f = (rampT > 0 && t < rampT ? f0 * Math.pow(f1 / f0, t / rampT) : rampT > 0 ? f1 : f0) * det;
    const dt = f / SR;
    let v;
    switch (type) {
      case 'sine':
        v = Math.sin(2 * Math.PI * ph);
        break;
      case 'triangle':
        v = 1 - 4 * Math.abs(ph - 0.5);
        break;
      case 'square':
        v = (ph < 0.5 ? 1 : -1) + polyblep(ph, dt) - polyblep((ph + 0.5) % 1, dt);
        break;
      default:
        v = 2 * ph - 1 - polyblep(ph, dt);
    }
    ph += dt;
    if (ph >= 1) ph -= 1;
    n++;
    return v;
  };
}

/** RBJ biquad; frequency may be a function of time (seconds). */
function biquad(type, freq, Q = 0.707) {
  let x1 = 0, x2 = 0, y1 = 0, y2 = 0, n = 0;
  let b0, b1, b2, a1, a2;
  let lastF = -1;
  const calc = (f) => {
    const w = (2 * Math.PI * Math.min(f, SR * 0.45)) / SR;
    const cw = Math.cos(w), sw = Math.sin(w), al = sw / (2 * Q);
    let B0, B1, B2;
    if (type === 'lowpass') [B0, B1, B2] = [(1 - cw) / 2, 1 - cw, (1 - cw) / 2];
    else if (type === 'highpass') [B0, B1, B2] = [(1 + cw) / 2, -(1 + cw), (1 + cw) / 2];
    else [B0, B1, B2] = [al, 0, -al];
    const A0 = 1 + al;
    b0 = B0 / A0; b1 = B1 / A0; b2 = B2 / A0; a1 = (-2 * cw) / A0; a2 = (1 - al) / A0;
  };
  return (x) => {
    const f = typeof freq === 'function' ? freq(n / SR) : freq;
    if (f !== lastF) {
      calc(f);
      lastF = f;
    }
    const y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
    x2 = x1; x1 = x; y2 = y1; y1 = y;
    n++;
    return y;
  };
}

/** WebAudio-style envelope: linear attack to peak, exponential decay to 0.0005. */
const envAD = (peak, attack, decay) => (t) =>
  t < attack ? (peak * t) / attack : t > attack + decay ? 0 : peak * Math.pow(0.0005 / Math.max(peak, 1e-6), (t - attack) / decay);
const expRamp = (a, b, T) => (t) => (t >= T ? b : a * Math.pow(b / a, t / T));

/** Render `dur` seconds of src(t) * gain(t) into out at offset seconds. */
function add(out, at, dur, src, gain) {
  const s0 = Math.floor(at * SR);
  const n = Math.ceil(dur * SR);
  for (let i = 0; i < n; i++) {
    const j = s0 + i;
    if (j >= out.length) break;
    if (j < 0) continue;
    const t = i / SR;
    out[j] += src(t) * gain(t);
  }
}

function writeWav(name, data, normalize = 0) {
  let peak = 0;
  for (const v of data) peak = Math.max(peak, Math.abs(v));
  const k = normalize && peak > 0 ? normalize / peak : 1;
  const pcm = Buffer.alloc(44 + data.length * 2);
  pcm.write('RIFF', 0);
  pcm.writeUInt32LE(36 + data.length * 2, 4);
  pcm.write('WAVEfmt ', 8);
  pcm.writeUInt32LE(16, 16);
  pcm.writeUInt16LE(1, 20);
  pcm.writeUInt16LE(1, 22);
  pcm.writeUInt32LE(SR, 24);
  pcm.writeUInt32LE(SR * 2, 28);
  pcm.writeUInt16LE(2, 32);
  pcm.writeUInt16LE(16, 34);
  pcm.write('data', 36);
  pcm.writeUInt32LE(data.length * 2, 40);
  for (let i = 0; i < data.length; i++) {
    const v = Math.tanh(data[i] * k * 1.05);
    pcm.writeInt16LE(Math.round(Math.max(-1, Math.min(1, v)) * 32767), 44 + i * 2);
  }
  writeFileSync(OUT + name + '.wav', pcm);
  // Gain that restores the web build's relative mix after normalisation (capped against clipping).
  gains[name] = +(normalize && peak > 0 ? Math.min(1.3, peak / normalize) : 1).toFixed(3);
  return { name, sec: +(data.length / SR).toFixed(2), peak: +peak.toFixed(2) };
}

/** Fold a tail rendered past the loop end back onto the start for a seamless loop. */
function wrapLoop(data, loopLen) {
  const out = data.slice(0, loopLen);
  for (let i = loopLen; i < data.length; i++) out[i % loopLen] += data[i];
  return out;
}

/** Equal-power crossfade of the last `fade` seconds into the start (for noise beds). */
function crossfadeLoop(data, fade) {
  const f = Math.floor(fade * SR);
  const n = data.length - f;
  const out = data.slice(0, n);
  for (let i = 0; i < f; i++) {
    const a = i / f;
    out[i] = out[i] * Math.sin((a * Math.PI) / 2) + data[n + i] * Math.cos((a * Math.PI) / 2);
  }
  return out;
}

const tone = (out, at, freq, dur, type, vol, endFreq) =>
  add(out, at, dur + 0.02, oscillator(type, freq, endFreq ?? freq, endFreq ? dur : 0), (t) => (t < 0.005 ? (vol * t) / 0.005 : vol * Math.pow(0.0008 / vol, Math.min(1, (t - 0.005) / dur))));

const report = [];
const gains = {};

// ---------------------------------------------------------------- one-shot effects
{
  const d = buf(0.09);
  let lp = 0;
  for (let i = 0; i < d.length; i++) {
    const t = i / SR;
    lp += (noise() - lp) * 0.35;
    d[i] = (lp * 1.4 * Math.exp(-t / 0.016) + Math.sin(2 * Math.PI * 95 * t) * 0.9 * Math.exp(-t / 0.03)) * 0.8;
  }
  report.push(writeWav('gun', d));
}
function boom(dur, decay, thumpF, cutoff) {
  const d = buf(dur);
  let brown = 0, lp2 = 0;
  const f = biquad('lowpass', cutoff);
  for (let i = 0; i < d.length; i++) {
    const t = i / SR;
    brown = (brown + noise() * 0.08) * 0.995;
    lp2 += (noise() - lp2) * 0.12;
    const env = Math.min(1, t / 0.004) * Math.exp(-t / decay);
    const crackle = rnd() < 0.002 * Math.exp(-t / (decay * 0.6)) ? (rnd() - 0.5) * 2 : 0;
    const fr = thumpF * Math.exp(-t * 2.2) + 26;
    d[i] = f((brown * 3.2 + lp2 * 0.9 + crackle) * env) + Math.sin(2 * Math.PI * fr * t) * Math.exp(-t / (decay * 0.5)) * 0.9;
  }
  return d;
}
const boomBig = boom(2.6, 0.55, 70, 2400);
report.push(writeWav('boom_big', boomBig, 0.95));
report.push(writeWav('boom_small', boom(1.1, 0.22, 110, 3200), 0.9));
{
  const d = buf(1.4);
  const bp = biquad('bandpass', expRamp(2600, 500, 1.1), 1.2);
  add(d, 0, 1.4, () => bp(noise()), (t) => (t < 0.03 ? t / 0.03 : Math.pow(0.001, (t - 0.03) / 1.27)));
  tone(d, 0, 180, 0.08, 'sawtooth', 0.3, 60);
  report.push(writeWav('missile', d, 0.9));
}
{
  const d = buf(0.06);
  tone(d, 0, 2400, 0.03, 'square', 1, 1400);
  report.push(writeWav('hit', d, 0.8));
}
for (const heavy of [false, true]) {
  const d = buf(heavy ? 0.75 : 0.2);
  const lp = biquad('lowpass', heavy ? 900 : 2200);
  add(d, 0, heavy ? 0.7 : 0.15, () => lp(noise()), expRamp(heavy ? 0.9 : 0.35, 0.001, heavy ? 0.6 : 0.12));
  tone(d, 0, heavy ? 140 : 620, heavy ? 0.3 : 0.06, 'triangle', heavy ? 0.5 : 0.18, heavy ? 50 : 300);
  report.push(writeWav(heavy ? 'player_hit_heavy' : 'player_hit', d, 0.9));
}
{
  const d = buf(0.5);
  [0, 4, 7, 12].forEach((s, i) => tone(d, i * 0.05, midi(76 + s), 0.25, 'triangle', 0.12));
  report.push(writeWav('chime', d, 0.7));
}
{
  const d = buf(0.25);
  tone(d, 0, midi(84), 0.1, 'square', 0.05);
  tone(d, 0.06, midi(91), 0.14, 'square', 0.05);
  report.push(writeWav('bonus', d, 0.6));
}
{
  const d = buf(0.16);
  tone(d, 0, midi(72), 0.12, 'triangle', 0.1);
  report.push(writeWav('combo', d, 0.7));
}
{
  const d = buf(0.16);
  const bp = biquad('bandpass', 2400, 0.8);
  add(d, 0, 0.15, () => bp(noise()), expRamp(0.12, 0.001, 0.12));
  tone(d, 0.02, 1250, 0.07, 'sine', 0.06);
  report.push(writeWav('radio', d, 0.6));
}
{
  const d = buf(2.05);
  for (let i = 0; i < 4; i++) {
    tone(d, i * 0.5, 660, 0.22, 'square', 0.07, 640);
    tone(d, i * 0.5 + 0.25, 880, 0.22, 'square', 0.07, 860);
  }
  report.push(writeWav('klaxon', d, 0.7));
}
{
  const a = buf(0.14);
  tone(a, 0, 880, 0.12, 'sine', 0.14);
  report.push(writeWav('beep', a, 0.7));
  const b = buf(0.42);
  tone(b, 0, 1320, 0.4, 'sine', 0.14);
  report.push(writeWav('beep_final', b, 0.7));
}
{
  const d = buf(2.5);
  const bp = biquad('bandpass', expRamp(300, 1800, 1.6));
  add(d, 0, 2.5, () => bp(noise()), (t) => (t < 1.5 ? 0.05 + (0.45 * t) / 1.5 : 0.5 * Math.pow(0.002, (t - 1.5) / 0.9)));
  tone(d, 1.55, 90, 0.5, 'sine', 0.5, 40);
  report.push(writeWav('catapult', d, 0.9));
}
{
  const d = buf(0.14);
  tone(d, 0, 1800, 0.12, 'sawtooth', 0.05, 500);
  report.push(writeWav('flare', d, 0.5));
}
{
  const d = buf(1.05);
  const bp = biquad('bandpass', (t) => (t < 0.25 ? 600 * Math.pow(2200 / 600, t / 0.25) : 2200 * Math.pow(400 / 2200, Math.min(1, (t - 0.25) / 0.65))), 1.5);
  add(d, 0, 1.05, () => bp(noise()), (t) => (t < 0.22 ? t / 0.22 : Math.pow(0.001, (t - 0.22) / 0.78)));
  report.push(writeWav('whoosh', d, 0.8));
}
{
  const d = buf(3.0);
  tone(d, 0, 55, 2.8, 'sawtooth', 0.12, 41);
  tone(d, 0, 58.3, 2.8, 'sawtooth', 0.08, 43);
  for (let i = 0; i < boomBig.length && i < d.length; i++) d[i] += boomBig[i] * 0.35;
  report.push(writeWav('stinger', d, 0.9));
}
{
  const d = buf(0.05);
  tone(d, 0, 1900, 0.04, 'square', 0.05);
  report.push(writeWav('click', d, 0.5));
  const e = buf(0.06);
  tone(e, 0, 260, 0.05, 'square', 0.05);
  report.push(writeWav('dry', e, 0.5));
}

// ---------------------------------------------------------------- loops
function engine(roarCut, roarGain, whineF, whineGain, rumbleF, rumbleGain) {
  const d = buf(2.4);
  const lp = biquad('lowpass', roarCut);
  const wl = biquad('lowpass', 1400);
  const w = oscillator('sawtooth', whineF);
  const r = oscillator('sine', rumbleF);
  for (let i = 0; i < d.length; i++) d[i] = lp(noise()) * roarGain + wl(w()) * whineGain + r() * rumbleGain;
  return crossfadeLoop(d, 0.4);
}
report.push(writeWav('engine', engine(700, 0.6, 290, 0.06, 48, 0.25), 0.8));
report.push(writeWav('engine_boost', engine(2100, 0.9, 340, 0.05, 58, 0.35), 0.8));
{
  const d = buf(2.4);
  const bp = biquad('bandpass', 1000, 0.6);
  for (let i = 0; i < d.length; i++) d[i] = bp(noise());
  report.push(writeWav('wind', crossfadeLoop(d, 0.4), 0.7));
}
function gated(freq, rate, beats, duty, alt) {
  const len = Math.round((beats / rate) * SR);
  const d = new Float32Array(len);
  const lp = biquad('lowpass', alt ? 3500 : 3000);
  let ph = 0;
  for (let i = 0; i < len; i++) {
    const t = i / SR;
    const k = (t * rate) % 1;
    const f = alt ? ((t * rate) % 2 < 1 ? 1700 : 1350) : freq;
    ph = (ph + f / SR) % 1;
    const on = k < duty ? 1 : 0;
    d[i] = lp((ph < 0.5 ? 1 : -1) * on);
  }
  return d;
}
report.push(writeWav('lock_locking', gated(1150, 9, 4, 0.45, false), 0.6));
report.push(writeWav('lock_locked', gated(1550, 10, 1, 1.01, false), 0.6));
report.push(writeWav('alert_slow', gated(0, 7, 2, 0.5, true), 0.65));
report.push(writeWav('alert_fast', gated(0, 14, 2, 0.5, true), 0.65));

// ---------------------------------------------------------------- music
class Track {
  constructor(bars, bpm) {
    this.step = 60 / bpm / 4;
    this.len = Math.round(bars * 16 * this.step * SR);
    this.d = new Float32Array(this.len + SR * 3);
  }
  kick(t, vol) {
    add(this.d, t, 0.4, oscillator('sine', 150, 42, 0.13), envAD(vol, 0.002, 0.32));
  }
  snare(t, vol) {
    const hp = biquad('highpass', 1300);
    add(this.d, t, 0.25, () => hp(noise()), envAD(vol, 0.002, 0.17));
    add(this.d, t, 0.15, oscillator('triangle', 200, 120, 0.08), envAD(vol * 0.6, 0.002, 0.09));
  }
  hat(t, vol, open = false) {
    const hp = biquad('highpass', 7500);
    add(this.d, t, 0.3, () => hp(noise()), envAD(vol, 0.001, open ? 0.22 : 0.035));
  }
  crash(t, vol) {
    const hp = biquad('highpass', 4500);
    add(this.d, t, 1.5, () => hp(noise()), envAD(vol, 0.002, 1.3));
  }
  tom(t, note, vol) {
    add(this.d, t, 0.3, oscillator('sine', midi(note), midi(note) * 0.55, 0.2), envAD(vol, 0.002, 0.25));
  }
  bass(t, note, dur, vol, bright = 1) {
    const o = oscillator('sawtooth', midi(note));
    const f0 = 260 + 1300 * bright;
    const lp = biquad('lowpass', expRamp(f0, 180, dur), 6);
    add(this.d, t, dur + 0.05, () => lp(o()), envAD(vol, 0.004, dur));
  }
  lead(t, note, dur, vol, type = 'square') {
    for (const det of [-6, 6]) {
      const o = oscillator(type, midi(note), midi(note), 0, det);
      const lp = biquad('lowpass', 2600);
      add(this.d, t, dur + 0.05, () => lp(o()), envAD(vol * 0.5, 0.008, dur));
    }
  }
  pluck(t, note, vol) {
    add(this.d, t, 0.35, oscillator('triangle', midi(note)), envAD(vol, 0.003, 0.28));
  }
  pad(t, notes, dur, vol) {
    const oscs = [];
    for (const n of notes) for (const det of [-9, 0, 9]) oscs.push(oscillator('sawtooth', midi(n), midi(n), 0, det));
    const lp = biquad('lowpass', 1100);
    add(
      this.d,
      t,
      dur + 0.05,
      () => lp(oscs.reduce((s, o) => s + o(), 0)),
      (x) => (x < dur * 0.3 ? (vol * x) / (dur * 0.3) : Math.max(0, vol * (1 - (x - dur * 0.3) / (dur * 0.7)))),
    );
  }
  render(bars, fn) {
    for (let i = 0; i < bars * 16; i++) {
      const s = i % 16;
      const bar = Math.floor(i / 16) % 4;
      const phrase = Math.floor(i / 64);
      fn(bar, s, i * this.step, phrase);
    }
    return wrapLoop(this.d, this.len);
  }
}

const CALM_CHORDS = [[57, 60, 64], [53, 57, 60], [55, 60, 64], [55, 59, 62]];
const CALM_ROOTS = [45, 41, 48, 43];
const COMBAT_CHORDS = [[62, 65, 69], [58, 62, 65], [60, 64, 67], [61, 64, 69]];
const COMBAT_ROOTS = [38, 34, 36, 33];
const COMBAT_HOOK = [
  { 0: 74, 3: 77, 6: 81, 8: 79, 10: 77, 12: 76, 14: 74 },
  { 0: 77, 3: 74, 6: 70, 8: 72, 10: 74, 14: 77 },
  { 0: 76, 3: 79, 6: 84, 8: 82, 10: 81, 12: 79 },
  { 0: 81, 4: 80, 6: 76, 8: 73, 12: 76, 14: 81 },
];
const BOSS_CHORDS = [[64, 67, 71], [60, 64, 67], [62, 66, 69], [63, 66, 71]];
const BOSS_ROOTS = [40, 36, 38, 35];

{
  const tr = new Track(8, 108);
  const d = tr.render(8, (bar, s, t, phrase) => {
    const chord = CALM_CHORDS[bar];
    if (s === 0) tr.pad(t, chord, 2.4, 0.045);
    if (s === 0 || s === 10) tr.bass(t, CALM_ROOTS[bar], 0.4, 0.11, 0.3);
    if (s % 2 === 0) tr.pluck(t, chord[(s / 2) % 3] + 12 + ((s / 2) % 4 === 3 ? 12 : 0), 0.05);
    if (phrase > 0) {
      if (s === 0 || s === 8) tr.kick(t, 0.28);
      if (s === 4 || s === 12) tr.hat(t, 0.05, true);
    }
  });
  report.push(writeWav('music_calm', d, 0.85));
}
{
  const tr = new Track(8, 150);
  const d = tr.render(8, (bar, s, t, phrase) => {
    const root = COMBAT_ROOTS[bar];
    if (s % 4 === 0) tr.kick(t, 0.55);
    if (s === 4 || s === 12) tr.snare(t, 0.36);
    tr.hat(t, s % 2 === 0 ? 0.055 : 0.03, s % 4 === 2);
    if (s === 0 && bar === 0 && phrase % 2 === 0) tr.crash(t, 0.15);
    tr.bass(t, root + (s % 4 === 2 ? 12 : 0), 0.1, 0.16, 0.8);
    if (s === 0) tr.pad(t, COMBAT_CHORDS[bar], 1.6, 0.03);
    if (phrase % 2 === 1) {
      const n = COMBAT_HOOK[bar][s];
      if (n) tr.lead(t, n, 0.16, 0.07);
    } else if (s === 0 || s === 3 || s === 6 || s === 10) tr.lead(t, COMBAT_CHORDS[bar][s % 3] + 12, 0.08, 0.04);
  });
  report.push(writeWav('music_combat', d, 0.85));
}
function bossTrack(name, bpm, intensity) {
  const tr = new Track(8, bpm);
  const d = tr.render(8, (bar, s, t, phrase) => {
    const root = BOSS_ROOTS[bar];
    const chord = BOSS_CHORDS[bar];
    if ([0, 3, 6, 8, 11, 12, 14].includes(s)) tr.kick(t, 0.55);
    if (s === 4 || s === 12) tr.snare(t, 0.38);
    if (s === 15 && bar % 2 === 1) tr.snare(t, 0.15);
    tr.hat(t, s % 2 === 0 ? 0.06 : 0.035, s === 6 || s === 14);
    if (s === 0 && bar === 0) tr.crash(t, 0.18);
    tr.bass(t, root + (s % 4 === 2 ? 12 : 0), 0.1, 0.17, 0.9);
    if (bar === 3 && s >= 12) tr.tom(t, 50 - (s - 12) * 3, 0.3);
    if (phrase % 2 === 1 || intensity > 1) tr.lead(t, chord[(s * 2 + (s >> 2)) % 3] + 12 + (s % 8 >= 6 ? 12 : 0), 0.09, 0.05, 'sawtooth');
    if (s === 0) tr.pad(t, chord, 1.6, 0.03);
    if (intensity > 1 && s % 2 === 1) tr.hat(t, 0.04);
  });
  report.push(writeWav(name, d, 0.85));
}
bossTrack('music_boss', 160, 1);
bossTrack('music_final', 172, 2);

writeFileSync(OUT + 'gains.json', JSON.stringify(gains, null, 1));
console.table(report);
