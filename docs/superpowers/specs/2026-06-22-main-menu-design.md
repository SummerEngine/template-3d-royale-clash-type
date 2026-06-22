# Barbarian Field — Main Menu Design Spec

**Date:** 2026-06-22
**Status:** Approved (design)

## Concept

A Clash-of-Clans / Supercell styled main menu that becomes the app's entry
point. Epic splash art of barbarians battling on grass, three wooden-plank
buttons (Start / Options / Quit), and an audio Options panel. Built by a
**dynamic workflow** that fans out art generation in parallel, runs adversarial
**critic agents** to gate quality at each step, then assembles and reviews the
scene.

## Goals

- Bright, chunky Supercell look consistent with the game (no generic AI slop).
- Menu is the main scene; Start launches the existing diorama (`main.tscn`).
- Options screen with working Music + SFX volume controls.
- Reusable button sprite (normal + pressed) + text labels.
- Quality gated by critic agents, not first-shot output.

## Non-goals (YAGNI)

- No fullscreen/graphics/controls settings (audio-only options).
- No transitions/animations beyond simple show/hide of the options panel.
- No localization, no credits screen, no save slots.

## Scene architecture

New `res://scenes/menu.tscn` (main scene). Gameplay diorama stays at
`res://scenes/main.tscn`.

```
Menu (Control, full rect, anchors 0..1)
├── Splash (TextureRect, full rect, expand+keep-aspect-covered)
├── Buttons (VBoxContainer, centered, separation ~16)
│   ├── StartButton   (TextureButton)  + Label "Start"
│   ├── OptionsButton (TextureButton)  + Label "Options"
│   └── QuitButton    (TextureButton)  + Label "Quit"
├── OptionsPanel (Panel, visible=false, centered)
│   ├── Title Label "Options"
│   ├── MusicRow (HBox): Label "Music" + MusicSlider (HSlider 0..1)
│   ├── SfxRow   (HBox): Label "SFX"   + SfxSlider   (HSlider 0..1)
│   └── BackButton (TextureButton) + Label "Back"
└── (script) menu.gd on the Menu root
```

Each TextureButton uses the shared button sprite: `texture_normal` = normal
art, `texture_pressed` = pressed art. The Label is a child centered over the
button (buttons are sprite + overlaid text, per decision).

## Components & responsibilities

### menu.gd (on Menu root)
- Connects the three main button `pressed` signals + BackButton.
- `StartButton` → `get_tree().change_scene_to_file("res://scenes/main.tscn")`.
- `OptionsButton` → `OptionsPanel.visible = true`.
- `BackButton` → `OptionsPanel.visible = false`.
- `QuitButton` → `get_tree().quit()`.
- On `_ready`: load saved settings, apply to sliders + audio buses.
- Slider `value_changed` → set the matching bus volume + persist.

### Audio buses
- `res://default_bus_layout.tres` with **Master** and child buses **Music**,
  **SFX** (both routed to Master). Registered via project setting
  `audio/buses/default_bus_layout`.
- Slider value (linear 0..1) → `AudioServer.set_bus_volume_db(idx,
  linear_to_db(value))`; value 0 mutes (`set_bus_mute`).

### Settings persistence
- `user://settings.cfg` via `ConfigFile`: keys `audio/music`, `audio/sfx`
  (linear floats). Written on slider change, read on `_ready` (default 1.0).

## Assets (generated, Supercell/Clash style)

All imported under `res://assets/ui/` via the proven recipe:
`summer_generate_image` → take the hosted `fileUrl` → `summer_import_from_url`
into the project. (Verified: locally-placed files are NOT auto-imported by the
MCP and `file://` import is rejected, so import must come from a hosted URL.)

1. **splash.png** — "epic Clash of Clans barbarians clashing on a bright grassy
   battlefield, painterly Supercell mobile key-art, dramatic lighting,"
   landscape 16:9. greg's thumbnail passed as `referenceImageUrl` for style.
   Full-bleed image used as a background TextureRect.
2. **button_normal.png** — chunky wooden plaque button, stone/gold trim, blank
   center, **art fills the entire frame edge-to-edge** (no surrounding
   background, no margin). Used full-bleed as `texture_normal`.
3. **button_pressed.png** — same plaque pushed-in / darker, also full-bleed.

**Transparency decision:** buttons are **full-bleed rectangular plaques** rather
than cut-out sprites. The generator bakes a fake background and locally-stripped
files can't be re-imported via the MCP, so a cut-out would be unreliable. A
full-frame wooden plaque needs no alpha and imports cleanly from the hosted URL.
The per-asset critic enforces "fills the frame edge-to-edge, no border/bg."

## Build process — dynamic workflow with critics

The menu is built by a workflow (`Workflow` tool). Phases:

### Phase 1 — Generate art (parallel pipeline, one chain per asset)
For each of the 3 assets, independently:
1. **Generator agent** — generate the image (COC prompt), then import the hosted
   `fileUrl` to `res://assets/ui/` via `summer_import_from_url`.
2. **Critic agent (adversarial)** — judge against: Supercell-style match (no
   generic cel-shaded slop), correct subject, and for buttons that the plaque
   **fills the frame edge-to-edge with no background border**. Verdict
   {pass | regenerate, with reason}.
3. **Loop**: on "regenerate", feed the critic's reason back into a new
   generation. Cap at 3 rounds; keep the best-scored result if still failing,
   and `log()` that the cap was hit.

### Phase 2 — Assemble (sequential, single agent)
One agent (engine is single-instance; parallel scene edits would collide):
builds `menu.tscn` via the MCP using the returned asset paths, writes `menu.gd`,
creates the audio bus layout + settings persistence, and sets `menu.tscn` as the
main scene.

### Phase 3 — Review (critique the build)
- **Scene/script reviewer agent** audits `menu.tscn` + `menu.gd`: all signals
  wired, bus names exist, Start loads `main.tscn`, buttons reference the real
  sprite paths, no dead/`null` references, script compiles (via
  `summer_get_script_errors`). Returns a fix list.
- The assembler (or a fix agent) applies the fixes.
- **Completeness critic agent** — final "what's missing?" pass (unwired button,
  alpha not verified, main scene not set, options panel not hideable). Anything
  found becomes one more fix round.

### Phase 4 — Playtest (user)
Claude does not run the engine. User presses Play and confirms: menu shows with
splash + 3 styled buttons; Start loads the diorama; Options opens/closes and
sliders move; Quit exits.

## Data flow

`menu.gd` is the only stateful unit: it owns panel visibility, reads/writes
`settings.cfg`, and pushes slider values to the audio buses. The buttons and
sliders communicate to it purely via Godot signals. Assets are static textures
referenced by path. Each workflow agent communicates only through its structured
return value (asset path + critic verdict); no shared mutable state across the
parallel chains.

## Testing / verification

- Per-asset critic gate (style + alpha) during generation.
- Post-assembly scene/script review + `summer_get_script_errors` must be clean.
- Completeness critic before handoff.
- Final verification = **user playtest** (Claude never launches the engine).

## Risks / mitigations

- **Generator fakes transparency** → explicit bg-strip + alpha verify on buttons.
- **Critic loops forever** → 3-round cap, keep best, log the cap hit.
- **Engine single-instance conflicts** → all scene mutation in one sequential
  agent, never parallel.
- **Image generator ignores style reference** → critic rejects off-style output
  and regenerates with a sharpened prompt.
```
