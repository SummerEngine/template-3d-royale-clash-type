# Barbarian Field — Design Spec

**Date:** 2026-06-22
**Status:** Approved (design)

## Concept

A 3D mobile game in **landscape** orientation, rendered in a Clash of Clans /
Supercell art style. A large, flat grassy island sits in frame, and **greg**
(the user's rigged barbarian model) wanders around it on his own. A fixed 3/4
angled camera frames the whole field. There is no player input — it is a living
diorama / showcase scene.

## Goals

- Bright, cheerful, saturated COC/Supercell look.
- A large flat grassy ground that reads as a clean continuous surface (no grid
  seams).
- greg autonomously roams the field, staying within bounds and facing the
  direction he moves.
- Fixed angled camera that frames the entire island in landscape.

## Non-goals (YAGNI for this iteration)

- No player controls (no tap-to-move, no joystick).
- No gameplay systems (combat, resources, buildings).
- No real run-cycle animation in v1 (greg has no baked animations yet). This is
  an explicit **follow-up** via motion generation.
- No scattered props/decorations in v1 (optional later).

## Scene structure

```
Main (Node3D)                  # root, also the main scene
├── WorldEnvironment           # bright sky + warm ambient (COC mood)
├── Sun (DirectionalLight3D)   # warm key light, soft shadows
├── Ground (MeshInstance3D)    # the grassy island
├── Camera3D                   # fixed 3/4 angled view, landscape framing
└── Barbarian (greg.glb)       # instanced model + AutoWander.gd
```

## Components

### 1. Ground (the island)

- A **single large flat "island" mesh**: a wide, shallow box (e.g. a BoxMesh or
  hand-built mesh) with a bright vivid-green flat top and brown dirt sides — the
  classic COC island silhouette.
- **Rationale:** chosen over tiling the user's generated grass-cube assets
  because tiling produces visible grid seams. One clean mesh gives a smooth,
  continuous grass surface. (See memory: AI 3D bakes grids into tiles; user
  dislikes seams.)
- Flat, saturated materials: green top, brown sides. Low detail, toy-like.
- The top surface defines the wander bounds for greg (a rectangular area inset
  slightly from the edges so he doesn't walk off).

### 2. Barbarian (greg)

- Import `greg.glb` (asset id `dc124e36-b464-438f-8db1-d661e79d3d66`, rigged,
  no baked animations) into the project and instance it on the ground.
- `AutoWander.gd` behavior loop:
  1. Pick a random target point within the island's inset bounds.
  2. Rotate to face the target (smoothly).
  3. Walk toward it at a steady speed.
  4. On arrival, pause briefly (idle beat).
  5. Pick a new target; repeat.
- Movement is **glide-and-face** (translation + yaw) since there is no run
  animation yet. Optional subtle vertical bob to feel alive.
- Keep greg clamped inside bounds; never leaves the island.

### 3. Camera

- Fixed `Camera3D` at a downward 3/4 angle, positioned and zoomed to frame the
  entire island in landscape aspect.
- Static — does not follow or orbit.

### 4. Lighting / environment

- `WorldEnvironment` with a bright sky and warm ambient light.
- Warm `DirectionalLight3D` sun with soft shadows.
- Goal: sunny, saturated, cheerful COC mood.

### 5. Project settings

- Display orientation: **landscape**.
- Renderer: **mobile**.
- Main scene: the `Main` scene above.

## Data flow

`AutoWander.gd` owns the wander state machine. It holds the island bounds
(passed in or read from the Ground node), the current target, and movement
parameters (speed, turn rate, pause duration). Each frame it advances greg
toward the target, rotates him toward it, and on arrival transitions to a short
pause before choosing a new target. No other node depends on its internals —
the Ground exposes its bounds; the camera and lighting are static and
independent.

## Build order

The game lives in the `barbarian_game` project. The Summer Engine MCP can only
act on the project the running engine currently has open, so the user must open
this new project in the engine before build steps run.

1. Project settings (landscape + mobile + main scene).
2. Ground island mesh + materials.
3. Lighting + WorldEnvironment.
4. Camera framing.
5. Import greg + AutoWander script + place on ground.
6. **User playtests** (Claude does not drive the engine) — confirm greg wanders
   the field, stays in bounds, faces his movement, and the scene reads as COC.
7. *(Optional follow-up)* generate a real run-cycle animation for greg and wire
   it to play while moving / idle while paused.

## Testing / verification

- Verification is by **playtest in the engine, run by the user** (per project
  rule: Claude never launches the engine to test).
- Success criteria: landscape framing shows the whole grassy island; greg roams
  continuously without leaving the field and turns to face where he's going;
  the look is bright and Supercell-flavored.
```
