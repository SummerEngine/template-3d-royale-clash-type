# Arena Enclosure — Design Spec

**Date:** 2026-06-22
**Status:** Approved (design)
**Project:** `barbarian_game` (team-vs-team barbarian auto-battler)

## Concept

Physically enclose the 40×40 battle field in a **stylized stone octagon arena**
— a Clash of Clans / Supercell-flavored ring of chunky crenellated stone walls
and corner bastion towers. Today the field edges are empty and units invisibly
clamp at the boundary; this makes the arena read as a real contained
battlefield. The enclosure is **purely decorative** — containment stays in the
unit clamp, not in collision.

## Decisions (locked with user)

- **Border style:** stone fortress walls (not mountains/cliffs/water).
- **Build method:** AI-generate hero models — two distinct stone pieces
  generated via `summer_generate_3d`, then placed and repeated.
- **Footprint:** octagon.
- **Gates:** none — continuous crenellated walls + towers only.

## Geometry — the octagon

The octagon is the 40×40 square (`x,z ∈ [-20, 20]`) with its four corners
chamfered by `c = 8`. This yields 8 edges and 8 vertices:

**Straight wall runs** (axis-aligned, length `40 − 2c = 24`):
- North (`z = +20`): `(-12,+20) → (+12,+20)`
- South (`z = -20`): `(-12,-20) → (+12,-20)`
- East (`x = +20`): `(+20,-12) → (+20,+12)`
- West (`x = -20`): `(-20,-12) → (-20,+12)`

**Diagonal wall runs** (chamfers, length `c·√2 ≈ 11.3`):
- NE: `(+12,+20) → (+20,+12)`
- SE: `(+20,-12) → (+12,-20)`
- SW: `(-12,-20) → (-20,-12)`
- NW: `(-20,+12) → (-12,+20)`

**Tower vertices** (8): `(±12, ±20)` and `(±20, ±12)`.

## Camera-aware framing

The camera sits at `(0, 26, 26)` looking down the `−z` axis. So the **+z (north)
side is nearest the camera = foreground**, and the **−z (south) side is
farthest = background**.

- **Back & sides — tall:** South run, East run, West run, SE & SW diagonals →
  full crenellated walls (~6 units high); their towers ~8 units.
- **Front — low/open:** North run + NE & NW diagonals → low parapet (~1.5 units);
  the two front towers `(±12,+20)` shortened (~3 units) so the fight stays
  visible over them.

Bases land naturally inside: red `(+14,+14)` sits just inside the NE diagonal
(front-right, near camera, visible over the low parapet); blue `(-14,-14)` sits
inside the SW diagonal (back-left, visible because the camera is elevated).

## Gameplay-coupled change — octagon unit clamp

`battle_manager.gd` currently clamps units to a **square** (`±island_half_extent`,
19). An octagon cuts the corners, so a unit at `(19,19)` would stand *outside* a
diagonal wall. Tighten the clamp to the octagon, inset ~1 unit inside the walls:

```gdscript
# after the existing square clamp of p.x, p.z to ±island_half_extent:
var oct := absf(p.x) + absf(p.z)
if oct > 31.0:                  # diagonal walls at |x|+|z| = 32; inset 1
    var k := 31.0 / oct
    p.x *= k
    p.z *= k
```

This is the only script change; no other gameplay behavior moves.

## AI-generated assets (2 hero pieces, reused)

Generated via `summer_generate_3d`, downloaded to `res://models/`, referenced in
the scene **by import uid** (path-only refs get silently stripped):

1. **`wall_segment.glb`** — a chunky modular crenellated stone wall block,
   authored to tile end-to-end. Reused for every run (rotated for diagonals,
   y-scaled down for the low front parapet). Target footprint ~12 units long so a
   straight run = 2 segments and a diagonal run = 1 segment.
2. **`tower.glb`** — a chunky round/octagonal stone bastion with a crenellated
   top, placed at each of the 8 vertices (over the wall joints, hiding seams).

**Prompt direction (both):** *stylized Clash of Clans / Supercell, chunky
low-poly, crenellated battlements, warm hand-painted grey stone with subtle
moss, flat saturated, single clean object, no ground/base plate.*

**Per-asset verify-and-fix pass** (AI 3D is unreliable, per project memory):
confirm real geometry imported (not an empty node), correct/normalize scale,
strip any baked checkerboard/solid background masquerading as transparency,
verify the scene tree actually gained the node after instancing.

## Scene structure

New container under `Main`:

```
Main
└── Arena (Node3D)
    ├── Walls   (≈12 wall_segment instances, positioned + rotated around octagon)
    └── Towers  (8 tower instances at the vertices)
```

Walls/towers have **no collision** — they sit just outside the ±19 play area and
only frame it. Roughly 12 wall + 8 tower instances ≈ 20 nodes; fine for a static
diorama.

## Workstreams

- **WS1 — Assets (async, background):** generate `wall_segment.glb` + `tower.glb`
  as cloud jobs; poll; download to `res://models/`; verify/fix each. Requires the
  engine to have `barbarian_game` open.
- **WS2 — Code (local, parallel-safe):** apply the octagon clamp to
  `battle_manager.gd`. Pure local edit, no engine needed; runs while WS1 generates.
- **WS3 — Placement (engine, sequential, after WS1+WS2):** add `Arena` node;
  instance + position walls and towers; keep the front low/open.
- **WS4 — Framing & playtest:** tune camera if the tall back wall clips frame;
  then **the user opens the project and playtests** — Claude never drives the
  engine to test.

## Build order

1. Confirm the engine has `barbarian_game` open (MCP only acts on the open
   project). If not, ask the user to open it.
2. **Parallel:** kick off WS1 generations *and* apply WS2 clamp edit.
3. When assets land: verify/fix each GLB.
4. WS3: add `Arena`, instance walls (2 per straight run, 1 per diagonal) and 8
   towers; apply tall/back vs low/front heights.
5. WS4: tune camera framing if needed.
6. **User playtests** in the engine.

## Verification

By **user playtest** (per project rule — Claude never launches the engine to
test). Success criteria:
- A stone octagon visibly frames the battle on all sides.
- Front is low/open so the fight stays fully visible.
- Reads as bright, chunky Clash of Clans / Supercell stone.
- No floating, z-fighting, or units standing outside the walls.
