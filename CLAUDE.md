# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

"Infinite Ski" — a single-file HTML5 canvas game (hackathon project for TartanHacks 2026). The entire game lives in `index.html` as inline JavaScript with no external dependencies. It renders a 3D skiing scene using a column raycaster, with a dog sled team, procedural terrain, and particle effects.

## Build & Serve

```bash
./build.sh    # Minifies index.html → dist/index.html, creates dist.tar.br
./serve.sh    # Decompresses dist.tar.br and serves on localhost:8000
```

**Size budget: 15KB** — `build.sh` fails if `dist.tar.br` exceeds 15,360 bytes. Requires `html-minifier-terser` (auto-installed via npm) and `brotli`.

## Architecture

Everything is in `index.html` — no build system, no modules, no frameworks.

- **Audio**: ZzFX Micro inline synthesizer (top of script)
- **Terrain**: `getHeight(x,z)` is the single source of truth for world height — sum of sine waves with a downhill slope bias. `curvature(z)` adds lateral path bending. `terrainType(i)` returns friction zones
- **Rendering**: `renderTerrain()` is a column raycaster that marches rays per screen column with distance fog. `drawMtn()` draws parallax mountain ranges. `drawDog()`/`drawSled()` render the pixel-art dog team and sled via canvas fillRect
- **Physics**: In `update(dt)` — gravity based on terrain slope, friction by terrain type, turn drag, air drag. Speed clamped to [7.5, 30]. Player Y snaps to `getHeight(pX, pZ)` each frame
- **Camera**: Spring-arm follow cam with lerp smoothing, yaw tracks a point ahead of player. FOV adjusts dynamically based on slope
- **Game states**: `state` — 0=title, 1=playing, 2=game over. High score persisted to localStorage

## Key Constraints

- All code must remain in a single HTML file to meet the hackathon submission format
- Every byte counts — keep the brotli-compressed tar under 15KB
- No external assets or CDN dependencies
