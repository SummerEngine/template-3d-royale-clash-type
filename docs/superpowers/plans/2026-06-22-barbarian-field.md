# Barbarian Field Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement this plan
> task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** A 3D landscape mobile diorama — a Clash-of-Clans-style grassy island
with greg the barbarian auto-wandering it under a fixed 3/4 camera.

**Architecture:** A single `Main` Node3D scene holds a WorldEnvironment, a warm
sun, a flat "island" ground mesh, a fixed Camera3D, and an instance of greg
driven by `AutoWander.gd`. Scaffolded on disk first so the user can open it, then
built out node-by-node via the Summer Engine MCP.

**Tech Stack:** Summer Engine 0.5.42 (Godot 4.6 base), GDScript, GLB model
(greg, asset id `dc124e36-b464-438f-8db1-d661e79d3d66`).

**Key constraints (project rules):**
- The MCP only acts on the project the engine currently has open. The user must
  open `barbarian_game` in the engine before any MCP task runs.
- Claude never launches/runs the engine to test — the user playtests.
- No defensive clamps/floors on gameplay tunables; ship raw tuned values.

---

### Task 0: Scaffold the on-disk Godot project (no engine needed)

**Files:**
- Create: `project.godot`
- Create: `scenes/main.tscn`
- Create: `scripts/.gdignore` (none — placeholder dir created by main script later)

- [ ] **Step 1: Write `project.godot`**

```ini
; Engine configuration file.
config_version=5

[application]
config/name="Barbarian Field"
config/description="A 3D mobile landscape diorama: a Clash of Clans style grassy island with a wandering barbarian."
run/main_scene="res://scenes/main.tscn"
config/features=PackedStringArray("4.6", "Mobile")

[display]
window/size/viewport_width=1280
window/size/viewport_height=720
window/handheld/orientation="landscape"
window/stretch/mode="canvas_items"
window/stretch/aspect="expand"

[rendering]
renderer/rendering_method="mobile"
renderer/rendering_method.mobile="mobile"
```

- [ ] **Step 2: Write a minimal `scenes/main.tscn`**

A single Node3D root named `Main` so the project opens cleanly. All other nodes
are added via MCP once open (so assets get correct UIDs — hand-wiring asset paths
gets stripped by Godot).

```
[gd_scene format=3 uid="uid://bbarbfield0001"]

[node name="Main" type="Node3D"]
```

- [ ] **Step 3: Verify files exist on disk**

Confirm `project.godot` and `scenes/main.tscn` are present. No engine call.

- [ ] **Step 4: Hand off to user**

Tell the user: open `barbarian_game` in Summer Engine. Wait for confirmation +
`summer_get_project_context` showing `application/config/name = "Barbarian Field"`
before any further task.

---

### Task 1: Confirm project is open and settings are correct

**Tool:** `summer_get_project_context`, `summer_project_setting`

- [ ] **Step 1: Confirm the right project is open**

Call `summer_get_project_context`. Verify `project.name` / `config/name` is
"Barbarian Field" and `main_scene` is `res://scenes/main.tscn`.
Expected: matches. If it still shows "Hex Island", STOP and ask the user to open
the new project.

- [ ] **Step 2: Verify orientation + renderer settings**

Confirm `display/window/handheld/orientation = "landscape"` and
`rendering/renderer/rendering_method = "mobile"`. If missing (engine rewrote the
file), set them:
- `summer_project_setting` key `display/window/handheld/orientation` = `"landscape"`
- `summer_project_setting` key `rendering/renderer/rendering_method` = `"mobile"`

- [ ] **Step 3: Open the main scene**

Call `summer_open_main_scene`, then `summer_get_scene_tree`.
Expected: tree shows root `Main` (Node3D), no children yet.

---

### Task 2: Build the ground island

**Tool:** `summer_add_node`, `summer_set_prop` (or `summer_batch`)

- [ ] **Step 1: Add the Ground mesh node**

Add a `MeshInstance3D` named `Ground` under `Main`.

- [ ] **Step 2: Give it a flat box "island" mesh**

Set `Ground.mesh` to a new `BoxMesh` with `size = (40, 1.5, 40)` (wide, shallow
slab). Position `Ground` at `(0, -0.75, 0)` so the top surface sits at world y=0.

- [ ] **Step 3: Apply COC-style materials**

Create a `StandardMaterial3D` for the top — bright vivid green
(`albedo_color = (0.36, 0.72, 0.22)`), `roughness = 1.0`, no metallic, flat
shaded look. Apply as the Ground's material override. (Brown sides are a v1.1
nicety; a uniform green slab reads fine for the first playtest — keep it simple.)

- [ ] **Step 4: Save and inspect**

`summer_save_scene`, then `summer_inspect_node` on `Ground` to confirm the mesh
size, transform, and albedo are set.
Expected: Ground is a 40×40 green slab with its top at y=0.

---

### Task 3: Lighting and environment

**Tool:** `summer_add_node`, `summer_set_prop`

- [ ] **Step 1: Add the sun**

Add a `DirectionalLight3D` named `Sun` under `Main`. Rotate it to a warm
late-morning angle, e.g. `rotation_degrees = (-50, -35, 0)`. Set
`light_color = (1.0, 0.96, 0.86)` (warm), `light_energy = 1.3`,
`shadow_enabled = true`.

- [ ] **Step 2: Add a WorldEnvironment**

Add a `WorldEnvironment` named `WorldEnvironment` under `Main`. Create an
`Environment` resource with:
- `background_mode = Sky` and a `ProceduralSkyMaterial` (bright blue sky), OR a
  solid bright sky-blue color if procedural sky is unavailable in
  gl/mobile — pick whichever the engine accepts.
- `ambient_light_source = Sky` (or color) with modest energy (~0.3) so shadows
  aren't black.
- `tonemap_mode = Filmic` for a pleasant, saturated look.

- [ ] **Step 3: Save and confirm**

`summer_save_scene`. Confirm via `summer_get_scene_tree` that `Sun` and
`WorldEnvironment` exist under `Main`.
Expected: scene is lit, bright, and cheerful (verified visually at playtest).

---

### Task 4: Fixed 3/4 camera

**Tool:** `summer_add_node`, `summer_set_prop`

- [ ] **Step 1: Add the camera**

Add a `Camera3D` named `Camera3D` under `Main`.

- [ ] **Step 2: Position and aim it**

Place it to frame the whole 40×40 island in landscape from a 3/4 angle:
- `position = (0, 26, 26)`
- `rotation_degrees = (-45, 0, 0)` (looking down at the island center)
- `fov = 50`

Tune position/fov so the island fills the landscape frame with a little margin.

- [ ] **Step 3: Make it current**

Set `Camera3D.current = true`.

- [ ] **Step 4: Save and confirm**

`summer_save_scene`, `summer_inspect_node` on `Camera3D`.
Expected: camera transform set, `current = true`. Final framing judged at
playtest.

---

### Task 5: Import greg and make him wander

**Tool:** `summer_import_asset_by_id`, `summer_instantiate_scene` /
`summer_add_node`, Write (`scripts/auto_wander.gd`), `summer_set_prop`

- [ ] **Step 1: Import greg into the project**

`summer_import_asset_by_id` with asset id
`dc124e36-b464-438f-8db1-d661e79d3d66` (greg). Note the resulting `res://` path
and UID the importer reports.

- [ ] **Step 2: Instance greg under Main**

Instance the imported greg scene/mesh as a child of `Main`, named `Barbarian`.
Position at `(0, 0, 0)` (on the ground top). If he's mis-scaled, set
`scale` so he reads ~1.5–2 units tall against the 40-unit island; confirm scale
at inspect time rather than guessing blindly.

- [ ] **Step 3: Write `scripts/auto_wander.gd`**

```gdscript
extends Node3D
# Auto-wander: pick a random point on the island, walk + turn toward it,
# pause on arrival, repeat. No player input. No baked run anim yet.

@export var half_extent: float = 17.0   # inset from the 20-unit island half-width
@export var move_speed: float = 4.0      # units/sec
@export var turn_speed: float = 6.0      # radians/sec slerp factor
@export var arrive_dist: float = 0.6
@export var pause_min: float = 0.4
@export var pause_max: float = 1.4
@export var bob_amount: float = 0.06
@export var bob_speed: float = 9.0

var _target: Vector3
var _pause_timer: float = 0.0
var _base_y: float = 0.0
var _bob_phase: float = 0.0

func _ready() -> void:
	_base_y = position.y
	_pick_target()

func _pick_target() -> void:
	_target = Vector3(
		randf_range(-half_extent, half_extent),
		_base_y,
		randf_range(-half_extent, half_extent)
	)

func _process(delta: float) -> void:
	if _pause_timer > 0.0:
		_pause_timer -= delta
		return

	var to_target := _target - position
	to_target.y = 0.0
	var dist := to_target.length()

	if dist <= arrive_dist:
		_pause_timer = randf_range(pause_min, pause_max)
		_pick_target()
		return

	var dir := to_target / dist

	# Face the direction of travel (yaw only), smoothly.
	var desired_yaw := atan2(dir.x, dir.z)
	rotation.y = lerp_angle(rotation.y, desired_yaw, clamp(turn_speed * delta, 0.0, 1.0))

	# Move.
	position += dir * move_speed * delta

	# Subtle bob so he feels alive without a real walk cycle.
	_bob_phase += bob_speed * delta
	position.y = _base_y + abs(sin(_bob_phase)) * bob_amount
```

- [ ] **Step 4: Attach the script to Barbarian**

Attach `res://scripts/auto_wander.gd` to the `Barbarian` node (the script
`extends Node3D`; `Barbarian` is the Node3D wrapper holding greg's model).

- [ ] **Step 5: Set wander bounds to match the island**

Confirm `half_extent` (17.0) keeps greg inside the 40×40 (half-width 20) island
with margin. Adjust only if the island size changed in Task 2. Do NOT add extra
clamps/floors — ship the tuned value.

- [ ] **Step 6: Save**

`summer_save_scene`.

---

### Task 6: User playtest (verification)

Claude does not run the engine. Ask the user to press Play and confirm:

- [ ] Landscape framing shows the whole grassy island.
- [ ] greg stands on the grass (not floating/sunken) at a sensible size.
- [ ] greg roams continuously, turning to face where he walks.
- [ ] greg never walks off the island.
- [ ] The scene looks bright and Supercell/COC-flavored.

If anything's off (scale, framing, lighting, bounds), iterate the relevant task,
re-save, and ask the user to re-test.

---

### Task 7 (optional follow-up): Real run animation for greg

Once the diorama is approved:

- [ ] Generate a run-cycle motion for greg via `summer_generate_motion`
      (he's rigged, so motion can target his skeleton).
- [ ] Import the animation and add an `AnimationPlayer` (or use the rig's).
- [ ] In `auto_wander.gd`, play "run" while moving and "idle" while paused
      (switch on `_pause_timer > 0.0`).
- [ ] User re-playtests.

---

## Self-Review

- **Spec coverage:** Ground (Task 2), barbarian + AutoWander (Task 5),
  camera (Task 4), lighting/env (Task 3), project settings (Tasks 0–1),
  build order + playtest verification (Task 6), optional run anim (Task 7). All
  spec sections covered.
- **Placeholders:** AutoWander script is complete; MCP calls name exact
  nodes/props/values. Sky-material choice in Task 3 is the one engine-dependent
  fork, with a stated fallback — resolved at build time, not a TODO.
- **Consistency:** Island half-width 20 (size 40) ↔ wander `half_extent` 17 ↔
  camera framing of a 40-unit island are consistent across Tasks 2, 4, 5.
- **Project rules honored:** disk scaffold before engine; user opens project;
  user playtests (no engine driving); no defensive clamps on tunables.
