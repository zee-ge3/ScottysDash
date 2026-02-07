# Scotty's Dash — Obstacle & Object Reference

All objects are rendered via Canvas 2D (`fillRect`, `beginPath`/`fill`, `stroke`) with no external assets. Every color passes through `fogCol(r,g,b)` which blends toward the sky color `rgb(192,221,240)` based on distance.

---

## Shared Infrastructure

### Fog Function
Used by every obstacle to fade into the distance:
```js
function fogCol(r, gv, b) {
  return `rgb(${(r*(1-fogT) + 192*fogT)|0},${(gv*(1-fogT) + 221*fogT)|0},${(b*(1-fogT) + 240*fogT)|0})`;
}
// fogT = Math.min(1, depth² × 0.0006)
```

### Seeded Random
Deterministic hash from two integers — ensures obstacles are identical at any world position across sessions:
```js
function seedRand(a, b) {
  let h = (a * 2654435761 ^ b * 2246822519) & 0x7fffffff;
  return (h % 10000) / 10000;
}
```

### Variant System
Each obstacle gets a `variant` value (0–1) from `seedRand(cz*31, cx*59)`. This single float drives all visual parameters (height, width, branch count, lean, color shift, etc.) through multiplications and thresholds, so each instance looks different without storing multiple seeds.

### Spawn Distribution
```js
let type = r2 < 0.32 ? 0    // 32% pine tree
         : r2 < 0.48 ? 1    // 16% rock
         : r2 < 0.6  ? 2    // 12% bare tree
         : r2 < 0.72 ? 3    // 12% log
         : r2 < 0.82 ? 4    // 10% boulder cluster
         : r2 < 0.92 ? 5    // 10% big rock
         :              6;   //  8% tree clump
```

### Collision Hitboxes
Per-type AABB in world units, scaled by obstacle's `scale` factor:
```js
let hx = ob.type === 1 ? 1.2    // rock
       : ob.type === 3 ? 1.8    // log (wide)
       : ob.type === 4 ? 1.3    // boulder cluster
       : ob.type === 5 ? 1.8    // big rock
       : ob.type === 6 ? 1.5    // tree clump
       : 0.7;                   // pine, bare tree (narrow)
let hz = ob.type === 3 ? 0.6    // log (shallow depth)
       : ob.type === 5 ? 1.5    // big rock
       : ob.type === 6 ? 1.2    // tree clump
       : 1.0;                   // default
// Collision if: |dz| < hz*scale AND |dx| < hx*scale
```

### Rendering Pipeline
All obstacles and skiers go through `renderObstacles()`:
1. Project each object's world position to screen via `project(x, getHeight(x,z), z)`
2. Ray-test line-of-sight from camera to object (12 samples) — if terrain blocks it, compute a crest clip region
3. Snap base Y to terrain silhouette buffer
4. Collect into `visible[]` array with `kind:'ob'` or `kind:'sk'`
5. Sort back-to-front by depth (`b.p.z - a.p.z`)
6. Render each with `g.save()` → optional crest clip → ground clip → draw → `g.restore()`

---

## Type 0: Pine Tree (32%)

Overlapping triangular foliage layers on a trunk. Two-pass rendering: all green first, then all snow on top.

**Variant-driven parameters:**
| Parameter | Range | Driven by |
|-----------|-------|-----------|
| Width multiplier | 0.6 – 1.25 | `vr` thresholds at 0.2, 0.5, 0.8 |
| Height multiplier | 0.7 – 1.15 | `vr` thresholds at 0.15, 0.4, 0.7 |
| Layer count | 2 – 4 | `vr` thresholds at 0.25, 0.75 |
| Green tint shift | -7.5 to +7.5 | `(vr-0.5)*15` |
| Snow coverage | 40% or 50% | `vr > 0.7` |
| Trunk knot | yes/no | `vr > 0.6` |

**Rendering:**
```js
// Base size
let h = sc * 16 * hMul;   // total height
let w = sc * 7.2 * wMul;  // total width

// Trunk: brown rectangle
g.fillStyle = fogCol(70, 45, 20);
g.fillRect(sx - tw/2, sy - h*0.25, tw, h*0.28);

// PASS 1: Green triangles (bottom-up, overlapping)
// spacing=h*0.22, layerH=h*0.35 → each layer overlaps the one below
for (let i = 0; i < layers; i++) {
  let baseY = sy - h*0.1 - spacing*i;
  let tipY = baseY - layerH;
  let lw = w * (1 - i*0.18);
  g.fillStyle = fogCol(20+i*8, 65+i*10+gShift, 28+i*5);
  // triangle: base corners → tip
  g.beginPath(); g.moveTo(sx-lw, baseY); g.lineTo(sx, tipY); g.lineTo(sx+lw, baseY);
  g.closePath(); g.fill();
}

// PASS 2: Snow triangles on top of all green
for (let i = 0; i < layers; i++) {
  let snowBaseY = baseY - layerH*(1-snowFrac);  // starts partway down
  let snowLw = lw * snowFrac * 1.4;             // proportional width
  g.fillStyle = fogCol(230, 240, 245);
  g.beginPath(); g.moveTo(sx-snowLw, snowBaseY);
  g.lineTo(sx, tipY); g.lineTo(sx+snowLw, snowBaseY);
  g.closePath(); g.fill();
}
```

**Key design decision:** Snow is drawn in a separate pass AFTER all green layers. This ensures snow visually overlaps the foliage below it, rather than getting buried by the next green layer above.

---

## Type 1: Rock (16%)

Four visual variants selected by `vr` threshold. Base size `sc * 12`.

### Variant A (vr < 0.25): Angular Rock
Asymmetric 5-vertex polygon. Three faces: dark base `(85,90,105)`, light face `(120,125,140)`, snow cap `(210,220,230)`.

### Variant B (0.25 ≤ vr < 0.5): Round Boulder
Organic 7-vertex shape with rounded silhouette. Same three-face shading approach.

### Variant C (0.5 ≤ vr < 0.75): Flat Wide Slab
Horizontally stretched 6-vertex polygon. Lower profile, wider footprint.

### Variant D (vr ≥ 0.75): Stacked Jagged Rocks
Two-tier geometry: base rock + smaller rock on top. Snow on the ledge between them and on the peak.

```js
// Example: Stacked jagged variant
// Base rock
g.fillStyle = fogCol(78, 82, 98);
g.beginPath();
g.moveTo(sx-sz*0.8, sy+bg); g.lineTo(sx-sz*0.9, sy-sz*0.4);
g.lineTo(sx-sz*0.4, sy-sz*0.9); g.lineTo(sx+sz*0.15, sy-sz*1.2);
g.lineTo(sx+sz*0.5, sy-sz*0.8); g.lineTo(sx+sz*0.7, sy+bg);
g.closePath(); g.fill();
// Top rock
g.fillStyle = fogCol(95, 100, 115);
g.beginPath(); g.moveTo(sx-sz*0.3, sy-sz*0.7);
g.lineTo(sx, sy-sz*1.4); g.lineTo(sx+sz*0.35, sy-sz*0.9);
g.closePath(); g.fill();
// Snow on ledge
g.fillStyle = fogCol(215, 225, 235);
g.fillRect(sx-sz*0.35, sy-sz*0.72, sz*0.55, sz*0.08);
```

All rocks are partially buried: `bg = sz * 0.35` pushes the base below the ground line.

---

## Type 2: Bare Tree (12%)

Stroke-based rendering (no fill polygons). Two structural variants.

### Standard (vr ≤ 0.85)
Single trunk with 2–5 branches alternating left/right. Trees with 4+ branches get sub-branches.

```js
let h = sc * 14;
let lean = (vr-0.5) * sc * 2;  // random lean
let nBranch = vr<0.2 ? 2 : vr<0.5 ? 3 : vr<0.8 ? 4 : 5;

// Trunk
g.strokeStyle = fogCol(60, 42, 25);
g.lineWidth = Math.max(1.5, sc * 1);
g.beginPath(); g.moveTo(sx, sy); g.lineTo(sx+lean, sy-h); g.stroke();

// Branches
g.lineWidth = Math.max(1, sc * 0.6);
for (let i = 0; i < nBranch; i++) {
  let t = 0.35 + i * 0.55/nBranch;    // position along trunk
  let dir = (i%2===0) ? -1 : 1;        // alternate sides
  let bx = sx + lean*t + dir*sc*(3+vr*3);
  let by2 = sy - h*(t + 0.15 + vr*0.05);
  g.beginPath(); g.moveTo(sx+lean*t, sy-h*t); g.lineTo(bx, by2); g.stroke();

  // Sub-branches on larger trees
  if (nBranch >= 4 && i > 0) {
    g.lineWidth = Math.max(1, sc * 0.35);
    g.beginPath(); g.moveTo(bx, by2);
    g.lineTo(bx + dir*sc*(1+vr), by2 - sc*(1+vr*0.5)); g.stroke();
  }
}
```

### Forked (vr > 0.85)
Trunk splits at 55% height into two diverging forks, each with a small branch.

---

## Type 3: Fallen Log (12%)

Horizontal cylinder lying on the ground. One clean-cut end shows growth rings; the other end is broken/splintered. Which end gets the circle is determined by `vr > 0.5` (flips via `g.scale(-1,1)`).

**Dimensions:**
```js
let logLen = sc * (8 + vr*6);     // 8–14 units long
let logH   = sc * (2.2 + vr*1.2); // 2.2–3.4 units tall
let angle  = (vr-0.5) * 0.3;      // slight rotation
```

**Structure (left-to-right after flip):**
1. **Shadow** — ellipse beneath: `rgba(0,0,0, 0.12*(1-fogT))`
2. **Body** — brown `fillRect`: `(72,50,28)`
3. **Bark highlight** — lighter strip on top 30%: `(92,65,35)`
4. **Dark underside** — bottom 20%: `(52,36,18)`
5. **Clean-cut end (left):**
   - Outer wood: `ellipse`, fill `(88,65,38)`
   - Inner wood: smaller `ellipse`, fill `(105,80,50)`
   - Growth rings: two `ellipse` strokes at r=0.22 and r=0.08, color `(62,42,22)`
6. **Broken end (right):**
   - Jagged bark edge: 6-vertex polygon, fill `(60,42,22)`
   - Splinter highlights: two small `fillRect`, `(80,58,32)`
7. **Snow on top** — `fillRect` across 80% of length
8. **Bark texture** — 3 vertical stroke lines

```js
// Clean-cut end with growth rings
g.fillStyle = fogCol(88, 65, 38);
g.beginPath(); g.ellipse(-logLen/2, -logH*0.5, logH*0.52, logH*0.52, 0, 0, PI*2); g.fill();
g.fillStyle = fogCol(105, 80, 50);
g.beginPath(); g.ellipse(-logLen/2, -logH*0.5, logH*0.35, logH*0.35, 0, 0, PI*2); g.fill();
g.strokeStyle = fogCol(62, 42, 22);
g.beginPath(); g.ellipse(-logLen/2, -logH*0.5, logH*0.22, logH*0.22, 0, 0, PI*2); g.stroke();
g.beginPath(); g.ellipse(-logLen/2, -logH*0.5, logH*0.08, logH*0.08, 0, 0, PI*2); g.stroke();

// Broken end — jagged bark polygon
g.fillStyle = fogCol(60, 42, 22);
let bx = logLen / 2;
g.beginPath();
g.moveTo(bx, -logH*0.05);
g.lineTo(bx + logH*0.15, -logH*0.25);
g.lineTo(bx - logH*0.1, -logH*0.45);
g.lineTo(bx + logH*0.2, -logH*0.65);
g.lineTo(bx + logH*0.05, -logH*0.85);
g.lineTo(bx, -logH);
g.closePath(); g.fill();
```

---

## Type 4: Boulder Cluster (10%)

2–3 rounded rocks grouped together. Base size `sc * 8`.

**Structure:**
1. **Main boulder** — 6-vertex polygon `(72,78,92)` with highlight triangle `(100,106,120)`
2. **Secondary boulder** — offset left or right based on `vr > 0.5`, smaller 5-vertex polygon `(80,86,100)`
3. **Third tiny rock** — only if `vr > 0.35`, very small 4-vertex polygon `(88,92,108)`
4. **Snow caps** — triangles on top surfaces of main and secondary rocks `(212,222,232)`

```js
// Secondary boulder offset
let ox = vr > 0.5 ? sz*0.6 : -sz*0.5;
g.fillStyle = fogCol(80, 86, 100);
g.beginPath();
g.moveTo(sx+ox - sz*0.4, sy + bg*0.5);
g.lineTo(sx+ox - sz*0.35, sy - sz*0.45);
g.lineTo(sx+ox + sz*0.1, sy - sz*0.6);
g.lineTo(sx+ox + sz*0.35, sy - sz*0.3);
g.lineTo(sx+ox + sz*0.3, sy + bg*0.5);
g.closePath(); g.fill();
```

---

## Type 5: Big Rock (10%)

Massive standalone boulder — largest single obstacle. Base size `sc * 14`.

**Structure (8-vertex main body with three visible faces):**
1. **Dark base face** — 8-vertex polygon `(65,70,85)` — the overall silhouette
2. **Right face** — lighter 6-vertex polygon `(90,95,112)` — suggests directional light
3. **Top face** — highlight 5-vertex polygon `(105,110,128)`
4. **Primary crack** — 3-point polyline stroke `(45,48,60)`, lineWidth `sc*0.3`
5. **Secondary crack** — 2-point stroke, thinner
6. **Snow cap** — 5-vertex polygon on top `(215,225,235)`
7. **Snow ledge** — `fillRect` on the crack shelf `(210,220,232)`

```js
// Main mass
g.fillStyle = fogCol(65, 70, 85);
g.beginPath();
g.moveTo(sx-sz*0.9,  sy+bg);
g.lineTo(sx-sz*1.0,  sy-sz*0.3);
g.lineTo(sx-sz*0.75, sy-sz*0.7);
g.lineTo(sx-sz*0.2,  sy-sz*1.05);
g.lineTo(sx+sz*0.3,  sy-sz*1.1);
g.lineTo(sx+sz*0.7,  sy-sz*0.8);
g.lineTo(sx+sz*0.95, sy-sz*0.35);
g.lineTo(sx+sz*0.85, sy+bg);
g.closePath(); g.fill();

// Crack/fissure detail
g.strokeStyle = fogCol(45, 48, 60);
g.lineWidth = Math.max(1, sc * 0.3);
g.beginPath();
g.moveTo(sx-sz*0.15, sy-sz*0.95);
g.lineTo(sx-sz*0.05, sy-sz*0.5);
g.lineTo(sx+sz*0.15, sy-sz*0.1);
g.stroke();
```

---

## Type 6: Tree Clump (8%)

3–4 pine trees packed tightly as a single obstacle. Uses the same two-pass snow rendering as single pines. Base size `sc*22` height, `sc*10` width.

**Layout:**
```js
let positions = [
  { dx: -baseW*0.8,  dh: 0.85+vr*0.1,  dw: 0.85 },  // left
  { dx:  baseW*0.6,  dh: 0.95,          dw: 0.95 },  // right
  { dx: -baseW*0.05, dh: 1.1+vr*0.15,  dw: 1.05 },  // center (tallest)
  { dx:  baseW*1.2,  dh: 0.78,          dw: 0.75 },  // far right (shortest)
];
let nTrees = vr < 0.3 ? 3 : 4;
```

**Two-pass rendering:**
```js
// PASS 1: All green foliage for all trees
for (let ti = 0; ti < nTrees; ti++) {
  // trunk + 2 overlapping triangle layers per tree
  for (let li = 0; li < 2; li++) {
    g.fillStyle = fogCol(18+li*10+ti*3, 60+li*12+gShift+ti*4, 25+li*5);
    // each tree gets slight color variation via ti offset
    g.beginPath(); g.moveTo(tx-lw2, bY); g.lineTo(tx, tY); g.lineTo(tx+lw2, bY);
    g.closePath(); g.fill();
  }
}
// PASS 2: All snow on top of everything
for (let ti = 0; ti < nTrees; ti++) {
  for (let li = 0; li < 2; li++) {
    g.fillStyle = fogCol(228, 238, 244);
    let snowBY = bY - layerH2*0.55;
    let snowLw = lw2 * 0.5;
    g.beginPath(); g.moveTo(tx-snowLw, snowBY);
    g.lineTo(tx, tY); g.lineTo(tx+snowLw, snowBY);
    g.closePath(); g.fill();
  }
}
```

---

## Crossing Skiers

Moving NPCs that traverse the slope laterally. Not grid-spawned — they use a distance trigger.

### Spawning
```js
// Spawn when player passes nextSkierZ
let side = seedRand(Math.floor(pZ), 9999) < 0.5 ? -1 : 1;
skiers.push({
  x: pX + side * (10 + Math.random()*6),  // 10–16 units off-center
  z: pZ + 18 + Math.random()*12,           // 18–30 units ahead
  vx: -side * (3.5 + Math.random()*2.5),   // 3.5–6 units/sec lateral
  vz: -0.3 + Math.random()*0.6,            // slight forward/back drift
  ph: Math.random() * PI * 2,               // animation phase
  active: false, hit: false,
  variant: Math.random()                     // jacket color
});
nextSkierZ = pZ + 35 + Math.random()*45;    // next spawn 35–80m ahead
```

### Movement
```js
// Activate when within 30 units
if (!sk.active && Math.abs(sk.z - pZ) < 30) sk.active = true;
if (sk.active) {
  sk.x += sk.vx * dt;
  sk.z += sk.vz * dt;
  sk.ph += dt * 8;  // animation speed
}
// Remove when behind or far away
if (sk.z < pZ - 20 || Math.abs(sk.x - pX) > 50) remove;
```

### Drawing
Render scale: `28 / depth`. Blocky pixel-art style (all `fillRect`). Flipped horizontally based on travel direction.

```js
function drawCrossingSkier(sx, sy, sc, dir, ph, fogT, variant) {
  g.save(); g.translate(sx, sy); g.scale(sc, sc);
  if (dir < 0) g.scale(-1, 1);
  let la = Math.sin(ph) * 0.5;  // leg/arm animation

  // Skis:      (55,55,60)   — fillRect(-6, 1, 13, 1)
  // Boots:     (40,40,48)   — 2× fillRect, 2×2
  // Legs:      (35,35,45)   — 2× fillRect, animated ±la
  // Jacket:    variant color — fillRect(-2, -9, 5, 5)
  // Arms:      variant color — 2× fillRect, animated ±la
  // Poles:     (140,140,145) — 2× fillRect, 1×7, animated
  // Head:      (210,175,145) — fillRect(-1, -12, 3, 3)
  // Hat:       jacket+20    — fillRect(-1, -14, 3, 2)
  // Goggles:   (30,30,35)   — fillRect(0, -11, 2, 1)

  g.restore();
}
```

**Jacket color variants (4 colors):**
| variant range | Color | RGB |
|--------------|-------|-----|
| < 0.25 | Blue | (50, 90, 170) |
| 0.25–0.5 | Red | (170, 45, 40) |
| 0.5–0.75 | Green | (45, 110, 55) |
| ≥ 0.75 | Orange | (190, 120, 35) |

### Collision
```js
if (Math.abs(sk.z - pZ) < 0.7 && Math.abs(sk.x - pX) < 0.5) → crash
```

### Snow Spray
Small white rectangles behind the skier when active:
```js
if (sk.active && Math.random() < 0.35) {
  g.fillStyle = `rgba(255,255,255,${0.25*(1-fogT)})`;
  g.fillRect(spX + random*sc2, baseY - random*sc2*0.5, sc2*0.4, sc2*0.2);
}
```

---

## LOS Occlusion System

All objects (obstacles + skiers) are tested for terrain occlusion before rendering:

```js
// Sample 8–12 points along the ray from camera to object
for (let s = 1; s < 12; s++) {
  let t = s / 12;
  let rx = camX + (ob.x - camX) * t;
  let rz = camZ + (ob.z - camZ) * t;
  let losY = camY + (wy - camY) * t;     // expected height along ray
  let terrainH = getHeight(rx, rz);        // actual terrain height
  let excess = terrainH - losY;            // positive = terrain blocks LOS
  if (excess > maxExcess) { maxExcess = excess; bestT = t; }
}
```

If occluded, a curved clip path follows the terrain profile at the blocking crest:
```js
if (crest) {
  // Sample terrain heights across crest, project to screen, create clip polygon
  g.beginPath();
  g.moveTo(fp.x, 0);       // top-left
  g.lineTo(lp.x, 0);       // top-right
  for (j = ns; j >= 0; j--) {  // follow crest curve right-to-left
    let wx = crest.x + (j/ns - 0.5) * span * 2;
    let cp = project(wx, getHeight(wx, crest.z), crest.z);
    g.lineTo(cp.x, cp.y);
  }
  g.closePath(); g.clip();
}
```

Objects also get a ground clip (`g.rect(-20, 0, W+40, baseY)`) so they don't draw below the terrain surface — critical for partially-buried rocks.