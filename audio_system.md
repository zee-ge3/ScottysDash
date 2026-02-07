# Audio System Documentation

All audio is procedural using the Web Audio API. Zero external files. Total memory: one 1-second noise buffer (~176KB at 44.1kHz) shared across 4 noise-based layers.

---

## Architecture Overview

```
                    ┌─────────────┐
                    │   Master    │ gain: 0.6
                    │   Gain      │ (fades to 0.15 on crash)
                    └──────┬──────┘
                           │
        ┌──────────┬───────┼────────┬──────────┬──────────┐
        │          │       │        │          │          │
   ┌────┴───┐ ┌───┴───┐ ┌─┴──┐ ┌───┴───┐ ┌───┴───┐ ┌───┴───┐
   │ Wind   │ │ Wind  │ │Pad │ │Runner │ │ Carve │ │Chime  │
   │ Main   │ │ Gust  │ │    │ │ Hiss  │ │       │ │ Bus   │
   └────────┘ └───────┘ └────┘ └───────┘ └───────┘ └───────┘
```

All layers connect to the master gain, which connects to `ax.destination`.

---

## 1. Shared Noise Buffer

```js
noiseBuf = ax.createBuffer(1, ax.sampleRate, ax.sampleRate);
let nd = noiseBuf.getChannelData(0);
for (let i = 0; i < nd.length; i++) nd[i] = Math.random() * 2 - 1;
```

One mono buffer, 1 second of white noise at native sample rate. Reused by 4 different `BufferSource` nodes (wind main, wind gust, runner hiss, carve), each looping independently. This is the only buffer allocation in the entire system.

---

## 2. Wind — Main Howl

```js
aWind = ax.createBufferSource(); aWind.buffer = noiseBuf; aWind.loop = true;
aWindF = ax.createBiquadFilter(); aWindF.type = 'bandpass';
aWindF.frequency.value = 400; aWindF.Q.value = 0.35;
aWindG = ax.createGain(); aWindG.gain.value = 0.15;
aWind → aWindF → aWindG → aMaster
```

**Signal chain:** `noise → bandpass(400Hz, Q=0.35) → gain(0.15) → master`

**Dynamic behavior (in updateAudio):**
```js
aWindG.gain.value = 0.1 + spd * 0.15;     // 0.10 at rest → 0.25 at full speed
aWindF.frequency.value = 250 + spd * 600;  // 250Hz at rest → 850Hz at full speed
```

The bandpass center sweeps up with speed, making wind higher-pitched when going fast. The wide Q (0.35) lets a broad frequency band through for a natural sound.

---

## 3. Wind — Gust Layer

```js
wn2 = ax.createBufferSource(); wn2.buffer = noiseBuf; wn2.loop = true;
wf2 = ax.createBiquadFilter(); wf2.type = 'bandpass';
wf2.frequency.value = 180; wf2.Q.value = 0.4;
wg2 = ax.createGain(); wg2.gain.value = 0.1;
wn2 → wf2 → wg2 → aMaster

// LFO modulates gust volume for surging
wLfo = ax.createOscillator(); wLfo.type = 'sine'; wLfo.frequency.value = 0.15;
wLfoG = ax.createGain(); wLfoG.gain.value = 0.06;
wLfo → wLfoG → wg2.gain
```

**Signal chain:** `noise → bandpass(180Hz, Q=0.4) → gain(0.1 ± 0.06 via LFO) → master`

A second, lower-pitched wind layer centered at 180Hz. The 0.15Hz LFO (one cycle every ~6.7 seconds) modulates its volume ±0.06, creating slow surging gusts that give the wind body and variation. This layer is static (not speed-reactive) — it's the ambient mountain wind always present.

---

## 4. Pad — Chord Synthesizer

```js
padF = ax.createBiquadFilter(); padF.type = 'lowpass';
padF.frequency.value = 400; padF.Q.value = 0.4;
aPadG = ax.createGain(); aPadG.gain.value = 0.18;

// 4 triangle oscillators for full chord voicing
for (let i = 0; i < 4; i++) {
  let o = ax.createOscillator(); o.type = 'triangle';
  o.frequency.value = chords[0][i];
  o → padF → aPadG → aMaster
}

// Breathing LFO on volume
lfo (sine, 0.06Hz) → lfoG (gain 0.06) → aPadG.gain

// Detuning shimmer LFO on 3rd oscillator
lfo2 (sine, 0.13Hz) → lfo2G (gain 0.5) → padOscs[2].detune
```

**Signal chain:** `4× triangle osc → lowpass(400Hz) → gain(0.18 ± 0.06 via LFO) → master`

### Chord Progression

```js
let chords = [
  [65.4, 130.8, 164.8, 196.0],  // Cmaj7: C2, C3, E3, G3
  [55.0, 130.8, 164.8, 196.0],  // Am7:   A1, C3, E3, G3
  [43.7, 130.8, 164.8, 174.6],  // Fmaj7: F1, C3, E3, F3
  [49.0, 123.5, 146.8, 196.0],  // G:     G1, B2, D3, G3
];
```

Chords cycle every 6–9 seconds with smooth `setTargetAtTime` glides (time constant 1.5s), so transitions take ~3 seconds to fully settle. The progression (I → vi → IV → V) creates a dreamy, wistful loop.

The breathing LFO (0.06Hz = one cycle every ~17 sec) gently swells the pad volume. The shimmer LFO (0.13Hz) detunes the 3rd oscillator ±0.5 cents, creating subtle chorusing.

---

## 5. Runner Hiss — Ski-on-Snow

```js
rn = ax.createBufferSource(); rn.buffer = noiseBuf; rn.loop = true;
aRunF = ax.createBiquadFilter(); aRunF.type = 'highpass';
aRunF.frequency.value = 2000; aRunF.Q.value = 0.3;
aRunG = ax.createGain(); aRunG.gain.value = 0;
rn → aRunF → aRunG → aMaster
```

**Signal chain:** `noise → highpass(2000Hz) → gain(0) → master`

**Dynamic behavior:**
```js
aRunG.gain.value = spd * 0.1;              // 0 at rest → 0.1 at full speed
aRunF.frequency.value = 1500 + spd * 2500; // 1500Hz → 4000Hz
```

High-frequency hiss that simulates sled runners on packed snow. Silent when still, grows to a bright sizzle at speed. The highpass cutoff rises with speed, making it brighter/thinner when going fast.

---

## 6. Carve Sound — Turn Scraping

```js
cn = ax.createBufferSource(); cn.buffer = noiseBuf; cn.loop = true;
aCarvF = ax.createBiquadFilter(); aCarvF.type = 'bandpass';
aCarvF.frequency.value = 600; aCarvF.Q.value = 0.6;
aCarvF2 = ax.createBiquadFilter(); aCarvF2.type = 'peaking';
aCarvF2.frequency.value = 1200; aCarvF2.gain.value = 5; aCarvF2.Q.value = 0.5;
aCarvG = ax.createGain(); aCarvG.gain.value = 0;
cn → aCarvF → aCarvF2 → aCarvG → aMaster
```

**Signal chain:** `noise → bandpass(600Hz, Q=0.6) → peaking(1200Hz, +5dB) → gain(0) → master`

The dual-filter design creates a deep, chunky snow-scraping tone. The bandpass at 600Hz sets the fundamental character, while the peaking filter at 1200Hz adds a mid-range edge.

### Burst Dynamics

```js
let ta = Math.abs(turnRate);
let turnDelta = ta - prevTurnAbs;

// Burst triggers on increasing turn intensity
if (turnDelta > 0.005 && ta > 0.15)
  carveBurst = Math.min(1, carveBurst + turnDelta * 8);

// Continuous decay
carveBurst *= Math.max(0, 1 - dt * 2.5);

// Two volume components: burst + steady
let steady = Math.min(1, ta * 1.2) * Math.max(0.3, spd) * 0.08;
carveVol = carveBurst * 0.25 + steady;

// Filter reacts to turn sharpness
aCarvF.frequency.value = 400 + ta * 350 + carveBurst * 200;
aCarvF.Q.value = 0.5 + carveBurst * 1.0;
```

**How it works:**

| Moment | carveBurst | steady | Total Vol | Filter Freq |
|--------|-----------|--------|-----------|-------------|
| No turn | 0 | 0 | 0 (silent) | 400Hz |
| Turn starts | jumps to ~0.4 | ~0.03 | ~0.13 | ~550Hz |
| Holding turn | decays toward 0 | ~0.06 | ~0.06 | ~480Hz |
| Turn sharpens | spikes again | ~0.08 | ~0.15 | ~600Hz |
| Turn releases | decays to 0 | drops to 0 | 0 | 400Hz |

The burst component (loud initial scrape) decays at 2.5×/second, so a sudden turn gives a pronounced *scrrrch* that fades to a quieter sustained hiss. The bandpass frequency also rises during bursts, making the initial scrape slightly brighter than the sustained sound.

**Thresholds:**
- `turnDelta > 0.005` — triggers on very small increases (turnRate changes ~0.01/frame)
- `ta > 0.15` — only activates during actual turns (deadzone filter)
- `spd` floor of 0.3 — ensures some carve sound even at low speed

---

## 7. Chime System — Crystal Bells

### Single Chimes

```js
function playChime() {
  let scale = chimeScales[chordIdx];  // chord-aware note selection
  let f = scale[random index];

  // Three oscillators for rich harmonics
  o1: sine at f           // fundamental
  o2: sine at f * 2.003   // detuned octave (shimmer)
  o3: sine at f * 3.01    // detuned 12th (sparkle)

  // o2 at 25% volume, o3 at 8% volume
  // Envelope: attack 0.2-0.3, decay via setTargetAtTime τ=0.7-1.5s
  // Auto-stop after 5 seconds
}
```

**Chord-aware scales:**

```js
let chimeScales = [
  [523.3, 659.3, 784.0, 1046.5, 1318.5],  // Over Cmaj7: C5, E5, G5, C6, E6
  [523.3, 659.3, 784.0, 880.0, 1046.5],    // Over Am7:   C5, E5, G5, A5, C6
  [523.3, 587.3, 698.5, 880.0, 1046.5],    // Over Fmaj7: C5, D5, F5, A5, C6
  [587.3, 784.0, 988.0, 1174.7, 1568.0],   // Over G:     D5, G5, B5, D6, G6
];
```

Notes are chosen from the pentatonic subset of the current chord, ensuring every chime harmonizes with the pad.

### Arpeggio Phrases

```js
function playArpPhrase() {
  let n = 2 or 3 notes;
  let base = random start position in scale;
  // Play ascending notes 0.18s apart
  // Each note: sine + detuned octave
  // Quick attack (30ms ramp), medium decay (τ=0.5-0.9s)
}
```

30% chance of arpeggio instead of single chime. Creates quick 2-3 note ascending runs that add melodic interest.

### Background Arpeggio Layer

```js
// Every 0.8-1.2 seconds during gameplay:
let f = scale[arpStep % scale.length] * 0.5;  // one octave below chime range
// Soft sine (gain 0.06-0.09), quick decay (τ=0.6s)
```

A gentle repeating pattern stepping through the current chord's scale an octave below the chimes. Creates a subtle melodic undercurrent.

### Chime Timing

```js
chimeTimer -= dt;
if (chimeTimer <= 0) {
  if (Math.random() < 0.3) {
    playArpPhrase();
    chimeTimer = 4 + Math.random() * 5;  // 4-9 sec gap after arp
  } else {
    playChime();
    chimeTimer = 2 + Math.random() * 4;  // 2-6 sec gap after single
  }
}
```

Chime bus gain: 0.18. All chime/arp oscillators route through `aChimeG`.

---

## 8. Crash Sound Effect

```js
function playCrashSfx() {
  // Generate 0.3 sec noise burst with exponential decay
  let len = ax.sampleRate * 0.3;
  let nb = ax.createBuffer(1, len, ax.sampleRate);
  for (let i = 0; i < len; i++)
    nd[i] = (Math.random() * 2 - 1) * Math.exp(-i / (ax.sampleRate * 0.08));

  // Route through lowpass at 800Hz for thuddy impact
  bs → lowpass(800Hz) → gain(0.4) → aMaster
}
```

One-shot buffer generated on demand (not stored). The exponential decay (τ=80ms) makes it a short thud. The 800Hz lowpass removes harsh high frequencies for a muffled impact feel. Called from both obstacle and skier collision handlers.

---

## 9. Master Volume Management

```js
// In updateAudio():
if (state == 2)  // crashed
  aMaster.gain.value = Math.max(0.15, aMaster.gain.value - dt * 0.5);
else
  aMaster.gain.value = Math.min(0.6, aMaster.gain.value + dt * 0.3);
```

On crash, master fades from 0.6 → 0.15 over ~0.9 seconds. On restart, fades back up over ~1.5 seconds.

---

## 10. Integration Points

### Initialization
```js
function startOrRetry() {
  initAudio();  // Creates AudioContext on first user interaction (browser policy)
  if (state == 0) { state = 1; resetGame(); }
  else if (state == 2 && crashTimer <= 0) { state = 0; }
}
```

### Frame Update
```js
function frame(t) {
  // ... game logic ...
  if (aInited) updateAudio(dt);  // runs every frame
}
```

### Crash Triggers (2 locations)
```js
// Obstacle collision:
crashed = 1; state = 2; crashTimer = 1.5; playCrashSfx();

// Skier collision:
sk.hit = true; crashed = 1; state = 2; crashTimer = 1.5; playCrashSfx();
```

---

## Gain Summary Table

| Layer | Init Gain | Dynamic Range | Source |
|-------|-----------|---------------|--------|
| Master | 0.6 | 0.15–0.6 (crash fade) | All layers |
| Wind main | 0.15 | 0.10–0.25 (speed) | Looped noise → bandpass |
| Wind gust | 0.10 | 0.04–0.16 (LFO) | Looped noise → bandpass |
| Pad chords | 0.18 | 0.12–0.24 (LFO) | 4× triangle osc → lowpass |
| Runner hiss | 0.0 | 0.0–0.10 (speed) | Looped noise → highpass |
| Carve | 0.0 | 0.0–0.25 (turn burst) | Looped noise → bandpass + peaking |
| Chime bus | 0.18 | static | Per-note oscillators |
| Crash SFX | 0.4 | one-shot | Generated noise burst |

## Memory Budget

| Item | Size |
|------|------|
| Noise buffer (1 sec mono) | ~176KB at 44.1kHz |
| 4 triangle oscillators (pad) | ~0 (generated in real-time) |
| 3 LFOs (sine oscillators) | ~0 (generated in real-time) |
| Per-chime oscillators | 2-3 oscs, auto-cleaned after 3-5 sec |
| Crash buffer (0.3 sec) | ~53KB, short-lived, GC'd after playback |
| **Total persistent** | **~176KB** |
