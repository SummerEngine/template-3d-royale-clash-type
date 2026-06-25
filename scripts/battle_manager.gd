extends Node
# Battle manager: the central brain of the team-vs-team barbarian auto-battler.
# Spawns two squads, answers targeting queries, runs soft-collision separation,
# handles player reinforcement input, and detects the winner.
# One Node placed under the scene root (Main).

const UNIT_GLB := preload("res://models/viking/Meshy_AI_Viking_Action_Figure__biped_Animation_Walking_withSkin.glb")
const BARB := preload("res://scripts/barbarian.gd")
const WIZARD_GLB := preload("res://models/wizard/Meshy_AI_Violet_Archmage_biped_Animation_Walking_withSkin.glb")
const WIZ := preload("res://scripts/wizard.gd")
const BUILDER_GLB := preload("res://models/dwarf/Meshy_AI_Flying_Dwarf_biped_Animation_Walking_withSkin.glb")
const BUILDER := preload("res://scripts/builder.gd")
# New units load at runtime (paths, not preload) so the manager still compiles before
# their freshly-unpacked GLBs have been imported by the editor. Same base-model
# convention as the others: the Walking GLB is the instanced body, extra clips merge in.
const GIANT_GLB_PATH := "res://models/giant/Meshy_AI_Barbarian_Behemoth_biped_Animation_Walking_withSkin.glb"
const GIANT_SCRIPT_PATH := "res://scripts/giant.gd"
const BOMBER_GLB_PATH := "res://models/skeleton/Meshy_AI_Bomb_Carrying_Skeleto_biped_Animation_Walking_withSkin.glb"
const BOMBER_SCRIPT_PATH := "res://scripts/bomber.gd"
const ELIXIR := preload("res://scripts/elixir.gd")
const ELIXIR_UI := preload("res://scripts/elixir_ui.gd")
const SFX := preload("res://scripts/sfx.gd")
const SPAWN_CARD := preload("res://scripts/spawn_card.gd")
const HOUSE_BAR := preload("res://scripts/house_health_bar.gd")
const HOUSE_HUD := preload("res://scripts/house_hud.gd")
const CAMERA_PAN := preload("res://scripts/camera_pan.gd")
const DEPLOY_CONTROLLER := preload("res://scripts/deploy_controller.gd")
const WIN_SCREEN := preload("res://scripts/win_screen.gd")
const CARD_CATALOG := preload("res://scripts/card_catalog.gd")
const PAUSE_MENU := preload("res://scripts/pause_menu.gd")

@export var player_base_path: NodePath
@export var enemy_base_path: NodePath
@export var squad_size: int = 4    # starting barbarians per team (split 2 left / 2 right)
@export var wizard_count: int = 0   # no wizards at start — both sides buy them later via elixir
@export var builder_count: int = 0   # no builders at start — bought later via elixir
@export var separation_strength: float = 0.5   # fraction of overlap resolved per physics frame (0..1); soft push
@export var island_half_extent: float = 19.0
@export var island_octagon_limit: float = 31.0   # |x|+|z| bound; diagonal arena walls sit at 32, units inset 1
@export var moat_half_width: float = 1.5     # perpendicular half-width of the real grass gap (slab inner edges at +/-1.5)
@export var bridge_offset: float = 9.1       # each bridge sits this far from centre along the moat (nudged out 0.1 to line up with the 3D deck)
@export var bridge_half_width: float = 2.6   # half the crossable gap at each bridge
@export var bridge_capture: float = 0.5      # only a small jostle just past a bridge edge is pulled back onto the lane; walk into the water any further and you're blocked + ejected straight back to your own bank (no long sideways teleport)
@export var bridge_arc_peak: float = 1.3     # visual height units rise to at a bridge's centre (tune to the deck)
@export var bridge_arc_span: float = 2.75    # perpendicular half-span where the deck meets the banks (height 0)
@export var enemy_start_elixir: float = 0.0      # enemy begins with this much (0 = ~9s behind the player's 3)
@export var enemy_brain_interval: float = 0.6    # how often the enemy AI considers a purchase (sec)
@export var enemy_barb_chance: float = 0.4       # P(barbarian) when the enemy buys at 3 elixir
@export var enemy_wizard_chance: float = 0.3     # P(wizard); builder gets the remainder (~0.3)
@export var spawn_button_size: float = 200.0     # on-screen player spawn button size (px)
@export var spawn_button_margin: float = 28.0    # spawn button inset from the screen corner (px)
@export var spawn_cost: float = 2.0              # elixir cost per barbarian
@export var wizard_spawn_cost: float = 3.0       # elixir cost per wizard (also the enemy's "wait for 3" gate)
@export var builder_spawn_cost: float = 4.0      # elixir cost per builder
@export var giant_spawn_cost: float = 4.0        # elixir cost per giant (enemy banks to this for one)
@export var bomber_spawn_cost: float = 1.0       # elixir cost per bomber (cheap, fragile suicide unit)
@export var enemy_bomber_chance: float = 0.12    # P(bomber) on an enemy purchase roll
@export var enemy_giant_chance: float = 0.08     # P(giant) on an enemy purchase roll (builder gets the remainder)

const SPAWN_CARD_GAP := 48.0   # px gap between spawn cards (clears both glow halos)

# Central moat geometry: it runs along the x+z=0 diagonal (perpendicular to the
# blue->red battle axis). MOAT_N points across it (the battle axis), MOAT_T along it.
const MOAT_N := Vector3(0.70710678, 0, 0.70710678)   # unit normal across the moat
const MOAT_T := Vector3(0.70710678, 0, -0.70710678)  # unit tangent along the moat

var units: Array = [[], []]   # units[0] = team 0 list, units[1] = team 1 list (Arrays of unit Node3Ds)
var _pumps: Array = []        # built structures: { "node": Node3D, "r": float } — units get shoved out, pumps never move
var _enemy_towers: Array = []  # [{node, pos}] the team-1 princess towers; a fallen one opens an enemy-side deploy strip
var _player_base   # HouseBase — untyped for cross-script duck typing
var _enemy_base    # HouseBase — untyped for cross-script duck typing
var _winner_shown: bool = false
var _elixir = null   # player elixir resource model (res://scripts/elixir.gd); untyped for duck typing
var _elixir_ui = null   # elixir HUD (res://scripts/elixir_ui.gd); untyped for duck typing
var _enemy_elixir = null   # enemy's HIDDEN elixir economy — same model, no HUD; fed by enemy pumps
var _sfx_spawn: AudioStreamPlayer = null    # success pop
var _sfx_denied: AudioStreamPlayer = null   # can't-afford buzz
var _music: AudioStreamPlayer = null        # looping background battle music
var _cam_pan = null                         # camera_pan.gd — suspended during a deploy drag

# --- TEMPORARY perf probe (remove after profiling) -------------------------
# Logs avg FPS + CPU process/physics times, and auto-A/Bs the grass shader vs a
# flat material every _PERF_WIN seconds so we can attribute per-frame cost on the
# real Android GPU. Strip this whole block (and the _process hook) once measured.
const _PERF_PROBE := true
const _PERF_WIN := 2.0
var _perf_t: float = 0.0
var _perf_flat: bool = false
var _perf_fps_accum: float = 0.0
var _perf_frames: int = 0
var _ground_mi: MeshInstance3D = null
var _grass_mat: Material = null
var _flat_mat: StandardMaterial3D = null

# Press-result codes shared with spawn_card.gd's on_press contract.
const _RESULT_IGNORED := 0
const _RESULT_SPAWNED := 1
const _RESULT_REJECTED := 2

func _ready() -> void:
	# Resolve the two team bases. Exported paths are used if present, but we fall
	# back to scanning siblings — exported NodePaths can get silently dropped when
	# the scene is saved, so we never hard-depend on them.
	_resolve_bases()
	_resolve_enemy_towers()

	# Listen for either base being destroyed to detect the winner.
	if is_instance_valid(_player_base):
		_player_base.destroyed.connect(_on_base_destroyed)
	if is_instance_valid(_enemy_base):
		_enemy_base.destroyed.connect(_on_base_destroyed)

	if not is_instance_valid(_player_base) or not is_instance_valid(_enemy_base):
		push_error("BattleManager: could not find both team bases (House/House2 with base.gd). Spawn aborted.")
		return

	# House health readouts: a floating bar over each house plus the fixed HUD.
	_setup_house_ui()

	# Subtle swipe-to-pan camera (drags a little, stays where you leave it).
	_setup_camera_pan()

	# Register the game-feel hub: the pan node drives camera shake; this manager
	# (a live Node) hosts world-space damage numbers / debris and hitstop timers.
	Juice.setup(_cam_pan, self)

	# Spawn both squads, each clustered in front of its own base.
	spawn_squad(0, _player_base, _enemy_base)
	spawn_squad(1, _enemy_base, _player_base)

	# SFX players, then the elixir economy/HUD (cards read its afford state on
	# build), then the player spawn cards, then the enemy auto-spawn.
	_setup_audio()
	_setup_elixir()
	_build_spawn_cards()
	_start_enemy_spawner()
	# In-match pause button (corner) + "PAUSED" overlay (Continue / Menu).
	add_child(PAUSE_MENU.new())
	SFX.play(self, "res://audio/gong", -2.0, 0.0)   # ceremonial gong to kick off the match
	# Announcer "FIGHT!" a beat after the gong (non-blocking, so _ready continues).
	get_tree().create_timer(0.4).timeout.connect(func() -> void:
		if is_instance_valid(self):
			SFX.play(self, "res://audio/announcer_fight", 2.0, 0.0, 0.64))

	# Collapse the decorative arena walls + corner towers into MultiMesh batches
	# (32 static draw calls -> 2). Purely visual; gameplay nodes are untouched.
	_batch_static_arena()

	if _PERF_PROBE:
		_setup_perf_probe()

# Find the two team bases. Try the exported paths first; otherwise scan our
# siblings for base.gd nodes and assign them by their `team` export. Robust to
# the exported NodePaths being lost on a scene save.
func _resolve_bases() -> void:
	if not player_base_path.is_empty():
		_player_base = get_node_or_null(player_base_path)
	if not enemy_base_path.is_empty():
		_enemy_base = get_node_or_null(enemy_base_path)
	if is_instance_valid(_player_base) and is_instance_valid(_enemy_base):
		return
	var parent := get_parent()
	if parent == null:
		return
	for sib in parent.get_children():
		if sib.has_method("take_damage") and sib.has_signal("destroyed"):
			var t = sib.get("team")
			if t == 0:
				_player_base = sib
			elif t == 1:
				_enemy_base = sib

# Spawn squad_size units clustered just in front of own_base, toward map center.
# Staggered: one entity per frame, so the full squad (units + wizards + builders)
# ramps in over a fraction of a second instead of instantiating and compiling all
# the rigged GLBs + their shaders in a single frame — that all-at-once burst was
# the multi-second freeze at the start of a match on mobile. Runs as a coroutine;
# both teams' spawns interleave across frames. Bails cleanly if the scene unloads
# mid-ramp.
func spawn_squad(team: int, own_base: Node3D, enemy_base: Node3D) -> void:
	# Direction from the base toward the origin (map center).
	var to_center := Vector3.ZERO - own_base.global_position
	to_center.y = 0.0
	var dir := to_center.normalized()
	var cluster_center := own_base.global_position + dir * 5.0
	cluster_center.y = 0.0

	# Split the squad into a left and a right group along the moat's lateral axis so
	# they set off down the two lanes (toward the bridges/towers). First half goes
	# to one side, second half to the other — a 4-squad starts 2 left / 2 right.
	# Pull the lanes in toward the centre line (the princess towers sit out at
	# +/-bridge_offset laterally) so the squad doesn't spawn directly behind a tower;
	# they still split left/right and route to the bridges from there.
	var lane_lateral := bridge_offset * 0.5
	var half := int(ceil(squad_size / 2.0))
	for i in squad_size:
		var lane: Vector3 = MOAT_T * lane_lateral
		if i >= half:
			lane = -lane
		var jitter := Vector3(randf_range(-1.2, 1.2), 0.0, randf_range(-1.2, 1.2))
		var spawn_pos := cluster_center + lane + jitter
		spawn_pos.y = 0.0
		_make_unit(team, enemy_base, spawn_pos)
		await get_tree().process_frame
		if not is_inside_tree() or not is_instance_valid(enemy_base):
			return

	# A few ranged wizards behind the front line (closer to own base).
	var wiz_center := own_base.global_position + dir * 2.5
	wiz_center.y = 0.0
	for i in wizard_count:
		var w_offset := Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
		var w_pos := wiz_center + w_offset
		w_pos.y = 0.0
		_make_wizard(team, enemy_base, w_pos)
		await get_tree().process_frame
		if not is_inside_tree() or not is_instance_valid(enemy_base):
			return

	# A couple of non-combat builders behind the line; they plant and "build".
	for i in builder_count:
		var b_offset := Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
		var b_pos := wiz_center + b_offset
		b_pos.y = 0.0
		_make_builder(team, enemy_base, b_pos)
		await get_tree().process_frame
		if not is_inside_tree() or not is_instance_valid(enemy_base):
			return

# A front-of-base spawn point (toward map center) with a small random jitter.
func _front_spawn_pos(own_base: Node3D) -> Vector3:
	var to_center := Vector3.ZERO - own_base.global_position
	to_center.y = 0.0
	var dir := to_center.normalized()
	var cluster_center := own_base.global_position + dir * 3.0
	var offset := Vector3(randf_range(-3.0, 3.0), 0.0, randf_range(-3.0, 3.0))
	var spawn_pos := cluster_center + offset
	spawn_pos.y = 0.0
	return spawn_pos

# Spawn a single reinforcement barbarian near own_base (front, small jitter).
func spawn_one(team: int, own_base: Node3D, enemy_base: Node3D) -> void:
	_make_unit(team, enemy_base, _front_spawn_pos(own_base))

# Spawn a single reinforcement wizard near own_base (front, small jitter).
func spawn_one_wizard(team: int, own_base: Node3D, enemy_base: Node3D) -> void:
	_make_wizard(team, enemy_base, _front_spawn_pos(own_base))

# Spawn a single reinforcement builder near own_base (front, small jitter).
func spawn_one_builder(team: int, own_base: Node3D, enemy_base: Node3D) -> void:
	_make_builder(team, enemy_base, _front_spawn_pos(own_base))

# Spawn a single giant near own_base (front, small jitter). Uses the generic typed
# path with the giant's runtime-loaded GLB + script (no preload — see the consts).
func spawn_one_giant(team: int, own_base: Node3D, enemy_base: Node3D) -> void:
	_make_typed(team, enemy_base, _front_spawn_pos(own_base), load(GIANT_GLB_PATH), load(GIANT_SCRIPT_PATH))

# Spawn a single bomber near own_base (front, small jitter).
func spawn_one_bomber(team: int, own_base: Node3D, enemy_base: Node3D) -> void:
	_make_typed(team, enemy_base, _front_spawn_pos(own_base), load(BOMBER_GLB_PATH), load(BOMBER_SCRIPT_PATH))

# Instantiate one barbarian, wire it up, and register it. Per the contract:
# setup() BEFORE add_child(), then global_position AFTER add_child().
func _make_unit(team: int, enemy_base: Node3D, spawn_pos: Vector3) -> void:
	var u = UNIT_GLB.instantiate()   # untyped: gains the Barbarian script below
	u.set_script(BARB)
	u.setup(team, self, enemy_base)
	add_child(u)
	u.global_position = spawn_pos
	units[team].append(u)

# Instantiate one ranged wizard, same contract as _make_unit but the WIZ script.
func _make_wizard(team: int, enemy_base: Node3D, spawn_pos: Vector3) -> void:
	var u = WIZARD_GLB.instantiate()   # untyped: gains the Wizard script below
	u.set_script(WIZ)
	u.setup(team, self, enemy_base)
	add_child(u)
	u.global_position = spawn_pos
	units[team].append(u)

# Instantiate one non-combat builder (dwarf), same contract as _make_unit.
func _make_builder(team: int, enemy_base: Node3D, spawn_pos: Vector3) -> void:
	var u = BUILDER_GLB.instantiate()   # untyped: gains the Builder script below
	u.set_script(BUILDER)
	u.setup(team, self, enemy_base)
	add_child(u)
	u.global_position = spawn_pos
	units[team].append(u)

# --- Static-prop batching (draw-call optimization) -------------------------
# Collapse the repeated, purely-decorative Arena props (24 wall segments + 8
# corner towers) into one MultiMeshInstance3D each: ~32 draw calls -> 2, no
# visual change. The originals stay in the .tscn (so they're still editable in
# the editor) but are freed at runtime once the batch stands in for them. The
# gameplay princess towers live at the scene ROOT (not under Arena), so the
# "Tower_"/"Wall_" Arena-children scan never reaches them.
func _batch_static_arena() -> void:
	var arena = get_parent().get_node_or_null("Arena")
	if arena == null:
		return
	_batch_group(arena, "Wall_", "WallsBatch")
	_batch_group(arena, "Tower_", "TowersBatch")

func _batch_group(arena, prefix: String, batch_name: String) -> void:
	var nodes: Array = []
	for c in arena.get_children():
		if String(c.name).begins_with(prefix):
			nodes.append(c)
	if nodes.is_empty():
		return
	var src_mi = _first_mesh_instance(nodes[0])
	if src_mi == null or src_mi.mesh == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = src_mi.mesh
	mm.instance_count = nodes.size()
	var inv: Transform3D = arena.global_transform.affine_inverse()
	for i in nodes.size():
		var mi = _first_mesh_instance(nodes[i])
		if mi != null:
			mm.set_instance_transform(i, inv * mi.global_transform)
	var mmi := MultiMeshInstance3D.new()
	mmi.name = batch_name
	mmi.multimesh = mm
	# GLB surface materials ride on the mesh itself; copy an override only if one exists.
	if src_mi.material_override != null:
		mmi.material_override = src_mi.material_override
	arena.add_child(mmi)
	for n in nodes:
		n.queue_free()

func _first_mesh_instance(n):
	if n is MeshInstance3D:
		return n
	for c in n.get_children():
		var f = _first_mesh_instance(c)
		if f != null:
			return f
	return null

# Targeting query: nearest living enemy unit by horizontal distance, or null.
func get_nearest_enemy(from_pos: Vector3, my_team: int) -> Node3D:
	var enemies: Array = units[1 - my_team]
	var best: Node3D = null
	var best_d: float = INF
	for e in enemies:
		if not is_instance_valid(e) or not e.alive:
			continue
		var to: Vector3 = e.global_position - from_pos
		to.y = 0.0
		var d := to.length()
		if d < best_d:
			best_d = d
			best = e
	# Enemy pumps are valid targets too — picked when nearer than any enemy unit.
	for pe in _pumps:
		if int(pe["team"]) == my_team:
			continue
		var pn = pe["node"]
		if not is_instance_valid(pn) or not pn.alive:
			continue
		var pto: Vector3 = pn.global_position - from_pos
		pto.y = 0.0
		var pd := pto.length()
		if pd < best_d:
			best_d = pd
			best = pn
	return best

# Nearest enemy STRUCTURE (princess tower / elixir pump — both register through the
# _pumps channel) to `from_pos`, or null. Used by the Giant, which ignores units and
# only smashes buildings. The King base is handled by the caller (it isn't a pump).
func get_nearest_enemy_structure(from_pos: Vector3, my_team: int) -> Node3D:
	var best: Node3D = null
	var best_d: float = INF
	for pe in _pumps:
		if int(pe["team"]) == my_team:
			continue
		var pn = pe["node"]
		if not is_instance_valid(pn) or not pn.alive:
			continue
		var to: Vector3 = pn.global_position - from_pos
		to.y = 0.0
		var d := to.length()
		if d < best_d:
			best_d = d
			best = pn
	return best

# Area-of-effect blast centered at `center`: deal `amount` to every ENEMY unit and
# every ENEMY building (princess tower / pump via _pumps, plus the enemy King base)
# whose horizontal distance is within `radius`. Used by the Bomber's suicide attack.
func explode_damage(center: Vector3, radius: float, amount: float, my_team: int) -> void:
	var r2 := radius * radius
	# Enemy units.
	var enemies: Array = units[1 - my_team]
	for u in enemies:
		if not is_instance_valid(u) or not u.alive:
			continue
		var dx: float = u.global_position.x - center.x
		var dz: float = u.global_position.z - center.z
		if dx * dx + dz * dz <= r2:
			u.take_damage(amount)
	# Enemy structures (towers + pumps).
	for pe in _pumps:
		if int(pe["team"]) == my_team:
			continue
		var pn = pe["node"]
		if not is_instance_valid(pn) or not pn.alive:
			continue
		var pdx: float = pn.global_position.x - center.x
		var pdz: float = pn.global_position.z - center.z
		if pdx * pdx + pdz * pdz <= r2:
			pn.take_damage(amount)
	# Enemy King base.
	var eb = _player_base if my_team == 1 else _enemy_base
	if is_instance_valid(eb) and eb.alive:
		var bdx: float = eb.global_position.x - center.x
		var bdz: float = eb.global_position.z - center.z
		if bdx * bdx + bdz * bdz <= r2:
			eb.take_damage(amount)

# A unit reports its death; remove it from whichever team array holds it.
func notify_died(unit: Node) -> void:
	for team_list in units:
		if team_list.has(unit):
			team_list.erase(unit)
			return

# A builder finished a pump; track it as an immovable obstacle (units get pushed
# out of its radius in _physics_process, like the team bases) AND as a targetable
# enemy structure (get_nearest_enemy scans these by team).
func register_pump(pump: Node3D, r: float, team: int) -> void:
	_pumps.append({ "node": pump, "r": r, "team": team })

# Route a unit moving from `from` toward `to` so it crosses the moat only at a
# bridge: same side of the water -> straight; crossing -> head to the nearer bridge
# gap (a point on the moat centre line) until across, then straight to the target.
func moat_route(from: Vector3, to: Vector3) -> Vector3:
	var sf := from.x + from.z
	var st := to.x + to.z
	if (sf >= 0.0) == (st >= 0.0):
		return to
	var along := from.dot(MOAT_T)
	var b_along := bridge_offset if along >= 0.0 else -bridge_offset
	# Aim at the bridge lane but just PAST the centerline onto the destination bank,
	# not exactly on the line. A unit that reaches the old on-the-line waypoint could
	# park there (still classified as "crossing", goal never advancing) and walk in
	# place forever; nudging it across guarantees sf flips and routing continues.
	var cross := MOAT_N * (signf(st) * (moat_half_width + 0.5))
	return MOAT_T * b_along + cross

# Visual-only deck height for a unit at `pos`: an arch that peaks at a bridge's
# centre line and falls to 0 at the banks, or 0 anywhere off a bridge. Units read
# this for their Y so they walk up and over the bridge without any real collision.
func bridge_height(pos: Vector3) -> float:
	var perp := pos.dot(MOAT_N)
	if absf(perp) >= bridge_arc_span:
		return 0.0
	var along := pos.dot(MOAT_T)
	var on_bridge := absf(along - bridge_offset) < bridge_half_width or absf(along + bridge_offset) < bridge_half_width
	if not on_bridge:
		return 0.0
	var t := perp / bridge_arc_span
	return bridge_arc_peak * (1.0 - t * t)

# True if `pos` is within `margin` of the moat centre line (the water + the bridge
# crossings). Builders use this so they never plant a pump in the channel.
func over_moat(pos: Vector3, margin: float) -> bool:
	return absf(pos.dot(MOAT_N)) < margin

# True if any live pump is within `min_dist` (horizontal) of `pos`. Builders use
# this to avoid planting a new pump on top of an existing one.
func pump_near(pos: Vector3, min_dist: float) -> bool:
	var md2 := min_dist * min_dist
	for pe in _pumps:
		var pn = pe["node"]
		if not is_instance_valid(pn):
			continue
		var dx: float = pn.global_position.x - pos.x
		var dz: float = pn.global_position.z - pos.z
		if dx * dx + dz * dz < md2:
			return true
	return false

# An elixir pump produced elixir for `team`. Both teams run an economy now: the
# player's drives the HUD, the enemy's is hidden and drives its AI. A pump feeds
# whichever side owns it, so building/destroying pumps shifts that team's income.
func add_elixir(team: int, amount: float) -> void:
	var econ = _elixir if team == 0 else _enemy_elixir
	if econ != null:
		econ.add(amount)

func _physics_process(_delta: float) -> void:
	# Gather all alive, valid units across both teams. A bomber mid-jump (_detonating)
	# is excluded so it phases through the crowd — it neither pushes nor is pushed while
	# leaping onto its target.
	var all: Array = []
	for team_list in units:
		for u in team_list:
			if is_instance_valid(u) and u.alive and not u.get("_detonating"):
				all.append(u)

	# Soft collision: for each unique pair, if they overlap horizontally push
	# them apart by a fraction of the overlap (separation_strength).
	var count := all.size()
	for i in range(count):
		var u_i = all[i]
		for j in range(i + 1, count):
			var u_j = all[j]
			var delta_pos: Vector3 = u_j.global_position - u_i.global_position
			delta_pos.y = 0.0
			var d := delta_pos.length()
			var min_d: float = u_i.radius + u_j.radius
			if d < min_d:
				var normal: Vector3
				if d > 0.001:
					normal = delta_pos / d
				else:
					# Coincident: nudge by a tiny deterministic offset per index.
					normal = Vector3(cos(float(i)), 0.0, sin(float(i)))
					d = 0.0
				var overlap := min_d - d
				var push := normal * overlap * 0.5 * separation_strength
				u_i.global_position -= push
				u_j.global_position += push

	# Push units out of either base: shove them to the base's ring if inside.
	for u in all:
		for b in [_player_base, _enemy_base]:
			if not is_instance_valid(b):
				continue
			var to: Vector3 = u.global_position - b.global_position
			to.y = 0.0
			var d := to.length()
			var min_d: float = b.radius + u.radius
			if d < min_d:
				var normal: Vector3
				if d > 0.001:
					normal = to / d
				else:
					normal = Vector3(1.0, 0.0, 0.0)
				var ring: Vector3 = b.global_position + normal * min_d
				u.global_position = Vector3(ring.x, 0.0, ring.z)

	# Push units out of every built pump too — structures never move; only units do.
	for i in range(_pumps.size() - 1, -1, -1):
		var pe: Dictionary = _pumps[i]
		var pn = pe["node"]
		if not is_instance_valid(pn):
			_pumps.remove_at(i)   # the pump was freed; drop it
			continue
		if not pn.alive:
			continue   # dying pump: let units walk through it
		var pr: float = pe["r"]
		for u in all:
			var to: Vector3 = u.global_position - pn.global_position
			to.y = 0.0
			var d := to.length()
			var min_d: float = pr + u.radius
			if d < min_d:
				var normal: Vector3 = (to / d) if d > 0.001 else Vector3(1.0, 0.0, 0.0)
				var ring: Vector3 = pn.global_position + normal * min_d
				u.global_position = Vector3(ring.x, 0.0, ring.z)

	# Keep units out of the central water moat. On a bridge lane crossing is fine; if
	# separation nudges a unit just off the lane edge (still over water) slide it back
	# ALONG onto the bridge rather than ejecting it across — so it can't be knocked off
	# the side. Only eject across to the near bank if it's genuinely in open water far
	# from any bridge.
	for u in all:
		var mperp: float = u.global_position.dot(MOAT_N)
		if absf(mperp) < moat_half_width:
			var malong: float = u.global_position.dot(MOAT_T)
			var mb: float = bridge_offset if malong >= 0.0 else -bridge_offset
			var moff: float = malong - mb
			if absf(moff) <= bridge_half_width:
				pass   # squarely on a bridge lane — let it cross
			elif absf(moff) <= bridge_half_width + bridge_capture:
				u.global_position += MOAT_T * (-signf(moff) * (absf(moff) - bridge_half_width))   # pull back onto the lane
			else:
				var ms: float = 1.0 if mperp >= 0.0 else -1.0
				u.global_position += MOAT_N * (ms * moat_half_width - mperp)

	# Clamp every unit to the island bounds and keep them on the ground plane.
	for u in all:
		var p: Vector3 = u.global_position
		p.x = clampf(p.x, -island_half_extent, island_half_extent)
		p.z = clampf(p.z, -island_half_extent, island_half_extent)
		# Project onto the octagon: pull corner-stragglers inside the diagonal walls.
		var oct: float = absf(p.x) + absf(p.z)
		if oct > island_octagon_limit:
			var k: float = island_octagon_limit / oct
			p.x *= k
			p.z *= k
		p.y = bridge_height(p)   # lift units into the bridge arc; 0 everywhere else
		u.global_position = p

func _process(_delta: float) -> void:
	if _PERF_PROBE:
		_perf_tick(_delta)
	# Player reinforcement: Space / Enter also spawns one extra blue unit (dev shortcut).
	if Input.is_action_just_pressed("ui_accept"):
		spawn_one(0, _player_base, _enemy_base)
	# DEBUG: press M for an instant player win (the _winner_shown guard fires it once).
	if Input.is_key_pressed(KEY_M) and not _winner_shown:
		_on_base_destroyed(1)   # enemy team "falls" -> player wins, runs the full win flow

# --- TEMPORARY perf probe implementation (remove after profiling) ----------
# Grab the Ground mesh + its grass material, and build a flat stand-in so we can
# A/B them. The flat material's color matches the grass mid-tone so the toggle is
# only a texture/shader-cost swap, not a brightness jump.
func _setup_perf_probe() -> void:
	var g = get_parent().get_node_or_null("Ground")
	if g is MeshInstance3D:
		_ground_mi = g
		_grass_mat = g.material_override
		_flat_mat = StandardMaterial3D.new()
		_flat_mat.albedo_color = Color(0.30, 0.62, 0.22)

# Per-frame: accumulate FPS, and every _PERF_WIN seconds print a line + flip the
# ground between the grass shader and the flat material. Comparing GRASS vs FLAT
# avg FPS isolates the grass fragment cost; proc/phys ms reveal CPU vs GPU bound.
func _perf_tick(delta: float) -> void:
	_perf_fps_accum += Performance.get_monitor(Performance.TIME_FPS)
	_perf_frames += 1
	_perf_t += delta
	if _perf_t < _PERF_WIN:
		return
	var avg_fps: float = _perf_fps_accum / float(max(_perf_frames, 1))
	var proc_ms: float = Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0
	var phys_ms: float = Performance.get_monitor(Performance.TIME_PHYSICS_PROCESS) * 1000.0
	var draws: int = int(Performance.get_monitor(Performance.RENDER_TOTAL_DRAW_CALLS_IN_FRAME))
	var n: int = units[0].size() + units[1].size()
	var mode: String = "FLAT " if _perf_flat else "GRASS"
	print("[PERF] %s avgfps=%.1f proc=%.2fms phys=%.2fms draws=%d units=%d" % [mode, avg_fps, proc_ms, phys_ms, draws, n])
	_perf_t = 0.0
	_perf_fps_accum = 0.0
	_perf_frames = 0
	# Grass A/B is done (it was free); leave the real grass on and just keep logging
	# fps/proc so we can verify the targeting-throttle fix on the next play.

# --- Player spawn cards (mobile-friendly, bottom-right corner) ---
# Three SpawnCard slots in a row (right -> left), built from the player's saved
# loadout: which 3 cards (of all in card_catalog.gd) sit in the hotbar is chosen on
# the Army screen and persisted to settings.cfg. Each card owns its glow halo,
# press juice, and afford pulse; gameplay (afford/spend/spawn) stays here.
func _build_spawn_cards() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var drop_tex := _load_texture("res://ui/elixir_drop.png")

	# One shared drag-to-deploy controller (owns the ghost, placement, commit).
	var deploy = DEPLOY_CONTROLLER.new()
	deploy.bind(self, get_viewport().get_camera_3d(), _player_base, _cam_pan)
	add_child(deploy)

	# Build one card per chosen loadout id, looked up in the catalog. Each card
	# hands the controller a unit_def: the model for the ghost + a positional spawn
	# fn (the generic spawn_one_typed_at, bound to this card's glb + script).
	var loadout: Array = CARD_CATALOG.load_loadout()
	# Size the cards to the actual screen width: the row fills the viewport minus an
	# even margin on each side, so the cards fit perfectly at any resolution / aspect
	# (and scale down on narrow screens instead of overflowing).
	var count := loadout.size()
	var avail := get_viewport().get_visible_rect().size.x
	var card_w := (avail - 2.0 * spawn_button_margin - float(count - 1) * SPAWN_CARD_GAP) / float(count)
	for slot in range(count):
		var def: Dictionary = CARD_CATALOG.by_id(str(loadout[slot]))
		if def.is_empty():
			continue
		var tex := CARD_CATALOG.load_texture(def["texture"])
		var glb = load(def["glb"])
		var unit_script = load(def["script"])
		var cost: float = def["cost"]
		var card := SPAWN_CARD.new()
		layer.add_child(card)
		_place_card(card, slot, count, card_w)   # slot 0 = leftmost; row spans the width
		card.setup(card_w, tex, cost, int(cost), drop_tex, _elixir, deploy,
			{ "glb": glb, "scale": def["scale"], "spawn_fn": spawn_one_typed_at.bind(glb, unit_script) })

# Center the row of `count` cards (each `card_w` wide) along the bottom edge.
# Anchored to the screen's bottom-center; total row width = viewport - 2*margin,
# so it spans the full width with even side margins at any resolution. Cards are
# square. slot 0 = leftmost card.
func _place_card(card: Control, slot: int, count: int, card_w: float) -> void:
	card.set_anchors_preset(Control.PRESET_CENTER_BOTTOM)
	var total_w := float(count) * card_w + float(count - 1) * SPAWN_CARD_GAP
	var left := -total_w * 0.5 + float(slot) * (card_w + SPAWN_CARD_GAP)
	card.offset_left = left
	card.offset_right = left + card_w
	card.offset_bottom = -spawn_button_margin
	card.offset_top = -spawn_button_margin - card_w

# Capture the two enemy (team-1) princess towers once, storing their world position
# so a fallen tower's lane is still locatable after the node frees itself.
func _resolve_enemy_towers() -> void:
	var parent := get_parent()
	if parent == null:
		return
	for n in ["TowerE_L", "TowerE_R"]:
		var t = parent.get_node_or_null(n)
		if t != null:
			_enemy_towers.append({ "node": t, "pos": t.global_position })

# World positions of destroyed enemy princess towers — each opens a deploy strip
# past the moat on its lane (read by deploy_controller.gd).
func destroyed_enemy_tower_positions() -> Array:
	var out: Array = []
	for e in _enemy_towers:
		var t = e["node"]
		if not is_instance_valid(t) or not t.get("alive"):
			out.append(e["pos"])
	return out

# --- Drag-to-deploy API (called by deploy_controller.gd) -------------------
# Can the player start a deploy of `cost` right now?
func can_deploy(cost: float) -> bool:
	return is_instance_valid(_player_base) and _player_base.alive \
		and _elixir != null and _elixir.can_afford(cost)

# Reject feedback when a deploy can't start or can't commit (meter shake + buzz).
func deploy_denied() -> void:
	_play(_sfx_denied)
	if _elixir_ui != null and _elixir_ui.has_method("reject"):
		_elixir_ui.reject()

# Commit a deploy at a chosen world position: re-check, spend, spawn. Returns a
# spawn_card result code (1 spawned / 2 rejected / 0 ignored).
func try_deploy(cost: float, spawn_fn: Callable, pos: Vector3) -> int:
	if not (is_instance_valid(_player_base) and _player_base.alive):
		return _RESULT_IGNORED
	if _elixir != null and not _elixir.can_afford(cost):
		deploy_denied()
		return _RESULT_REJECTED
	if _elixir != null:
		_elixir.spend(cost)
	spawn_fn.call(0, pos)
	_play(_sfx_spawn)
	return _RESULT_SPAWNED

# Positional spawns used by drag-to-deploy (team picks the matching enemy base).
func _enemy_base_for(team: int) -> Node3D:
	return _enemy_base if team == 0 else _player_base

func spawn_one_at(team: int, pos: Vector3) -> void:
	_make_unit(team, _enemy_base_for(team), pos)

func spawn_one_wizard_at(team: int, pos: Vector3) -> void:
	_make_wizard(team, _enemy_base_for(team), pos)

func spawn_one_builder_at(team: int, pos: Vector3) -> void:
	_make_builder(team, _enemy_base_for(team), pos)

# Generic positional spawn used by catalog-driven hotbar cards: the card binds its
# own glb + script, so any number of card types route through this one path.
func spawn_one_typed_at(team: int, pos: Vector3, glb, unit_script) -> void:
	_make_typed(team, _enemy_base_for(team), pos, glb, unit_script)

func _make_typed(team: int, enemy_base: Node3D, spawn_pos: Vector3, glb, unit_script) -> void:
	var u = glb.instantiate()
	u.set_script(unit_script)
	u.setup(team, self, enemy_base)
	add_child(u)
	u.global_position = spawn_pos
	units[team].append(u)

# --- SFX players -----------------------------------------------------------
func _setup_audio() -> void:
	# The generator padded both clips to ~1s; trim them to a snappy UI length.
	_sfx_spawn = _make_sfx("res://audio/spawn_pop.wav", -14.0, 0.22)
	_sfx_denied = _make_sfx("res://audio/spawn_denied.wav", -2.0, 0.16)
	_setup_music()

# Constant looping battle music, routed through the Music bus (slider-controlled).
func _setup_music() -> void:
	var path := "res://audio/battle_music.mp3"
	if not ResourceLoader.exists(path):
		return
	var s = load(path)
	if not (s is AudioStream):
		return
	if s is AudioStreamWAV:
		var ch := 2 if s.stereo else 1
		s.loop_mode = AudioStreamWAV.LOOP_FORWARD
		s.loop_begin = 0
		s.loop_end = s.data.size() / (2 * ch)   # loop the whole clip
	else:
		s.set("loop", true)   # mp3/ogg streams
	_music = AudioStreamPlayer.new()
	_music.stream = s
	_music.volume_db = -8.0
	if AudioServer.get_bus_index(&"Music") != -1:
		_music.bus = &"Music"
	add_child(_music)
	_music.play()

func _make_sfx(path: String, volume_db: float, length_secs: float) -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	if ResourceLoader.exists(path):
		var s = load(path)
		if s is AudioStream:
			_trim_wav(s, length_secs)
			p.stream = s
	p.volume_db = volume_db
	add_child(p)
	return p

# Slice an imported WAV stream down to `secs`, with a ~15ms fade-out on the tail
# so the hard cut doesn't click. No-op for compressed (IMA/QOA) formats.
func _trim_wav(stream: AudioStream, secs: float) -> void:
	if not (stream is AudioStreamWAV):
		return
	var w := stream as AudioStreamWAV
	var ch: int = 2 if w.stereo else 1
	var sample_bytes: int = 2 if w.format == AudioStreamWAV.FORMAT_16_BITS else (1 if w.format == AudioStreamWAV.FORMAT_8_BITS else 0)
	if sample_bytes == 0:
		return
	var frame_bytes: int = sample_bytes * ch
	var data: PackedByteArray = w.data
	var total_frames: int = data.size() / frame_bytes
	var max_frames: int = int(w.mix_rate * secs)
	if max_frames <= 0 or max_frames >= total_frames:
		return
	var d: PackedByteArray = data.slice(0, max_frames * frame_bytes)
	if w.format == AudioStreamWAV.FORMAT_16_BITS:
		var fade_frames: int = min(int(w.mix_rate * 0.015), max_frames)
		for i in range(max_frames - fade_frames, max_frames):
			var g: float = float(max_frames - i) / float(fade_frames)
			for c in range(ch):
				var off: int = (i * ch + c) * 2
				d.encode_s16(off, int(d.decode_s16(off) * g))
	w.data = d

func _play(p: AudioStreamPlayer) -> void:
	if p != null and p.stream != null:
		p.play()

# Build the house health readouts: a big billboarded bar floating over each
# house, plus the fixed on-screen HUD (player bottom-left, enemy top-right). The
# floating bars are added under us (a plain Node) so they live in world space and
# don't inherit the houses' ~8x scale.
func _setup_house_ui() -> void:
	var pbar = HOUSE_BAR.new()
	pbar.bind(_player_base)
	add_child(pbar)
	var ebar = HOUSE_BAR.new()
	ebar.bind(_enemy_base)
	add_child(ebar)

# Subtle swipe-to-pan camera. Created from code (no .tscn edit), binds the
# scene's current camera, and clamps panning to a small rectangle.
func _setup_camera_pan() -> void:
	var pan = CAMERA_PAN.new()
	pan.bind(get_viewport().get_camera_3d())
	add_child(pan)
	_cam_pan = pan

# Create the elixir resource model + its on-screen meter (drop + tube HUD).
func _setup_elixir() -> void:
	_elixir = ELIXIR.new()
	add_child(_elixir)
	var ui = ELIXIR_UI.new()
	ui.bind(_elixir)
	add_child(ui)
	_elixir_ui = ui
	# The enemy's mirror economy: identical elixir model (start/regen/max), no HUD.
	# It regenerates on its own and is topped up by enemy pumps via add_elixir().
	_enemy_elixir = ELIXIR.new()
	_enemy_elixir.start_elixir = enemy_start_elixir   # head start: enemy begins behind the player's 3
	add_child(_enemy_elixir)

# Load a UI texture. Prefer the imported resource; fall back to reading the PNG
# directly so it still works before Godot has imported the file (e.g. a freshly
# generated wizard_button.png with no .import yet).
func _load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null

# --- Enemy AI: spend the hidden elixir economy like a player would ----------
# A periodic brain tick: once the enemy can afford a 2-cost unit it commits to a
# purchase, weighted toward the cheap barbarian (cost 1) and occasionally a wizard
# or builder (cost 2). Because its elixir is fed by its own pumps, more pumps = a
# faster army; losing them starves it. One purchase per tick paces it like a player
# tapping cards rather than dumping a whole bank at once.
func _start_enemy_spawner() -> void:
	var timer := Timer.new()
	timer.name = "EnemyBrain"
	timer.wait_time = enemy_brain_interval
	timer.autostart = true
	timer.timeout.connect(_on_enemy_brain_tick)
	add_child(timer)

func _on_enemy_brain_tick() -> void:
	if not (is_instance_valid(_enemy_base) and _enemy_base.alive):
		return
	if _enemy_elixir == null or _enemy_elixir.current < wizard_spawn_cost:
		return   # bank to 3 (affords a barb or wizard); banks further for a 4-cost builder
	# Pick a unit type — balanced for variety. Only spawn if the roll is actually
	# affordable, so e.g. a 6-cost giant rolled at 3 just banks toward 6 instead of
	# spawning for free. Thresholds are cumulative; builder gets whatever's left.
	var r := randf()
	var t_barb := enemy_barb_chance
	var t_wiz := t_barb + enemy_wizard_chance
	var t_bomber := t_wiz + enemy_bomber_chance
	var t_giant := t_bomber + enemy_giant_chance
	if r < t_barb:
		if _enemy_elixir.spend(spawn_cost):
			spawn_one(1, _enemy_base, _player_base)
	elif r < t_wiz:
		if _enemy_elixir.spend(wizard_spawn_cost):
			spawn_one_wizard(1, _enemy_base, _player_base)
	elif r < t_bomber:
		if _enemy_elixir.spend(bomber_spawn_cost):
			spawn_one_bomber(1, _enemy_base, _player_base)
	elif r < t_giant:
		if _enemy_elixir.spend(giant_spawn_cost):
			spawn_one_giant(1, _enemy_base, _player_base)
	else:
		if _enemy_elixir.spend(builder_spawn_cost):
			spawn_one_builder(1, _enemy_base, _player_base)

# A base was destroyed: its team loses, the other team wins. Show it once.
func _on_base_destroyed(team: int) -> void:
	if _winner_shown:
		return
	_winner_shown = true
	if is_instance_valid(_music):
		_music.stop()   # gameplay theme ends the moment the match is decided
	var winner := 1 - team
	_play_end_music(winner == 0)
	# Announcer calls the result: "Victory!" for the player, "Defeat." otherwise.
	SFX.play(self, "res://audio/announcer_victory" if winner == 0 else "res://audio/announcer_defeat", 2.0, 0.0, 0.64)
	_show_win_banner(winner)

# Play a short victory/defeat track on the Music bus (slider-controlled). Prefers a
# dedicated *_music file; falls back to the existing victory/defeat stinger until
# the real tracks are generated, so this works now and auto-upgrades later.
func _play_end_music(win: bool) -> void:
	var stem := "victory" if win else "defeat"
	var path := ""
	for cand in [
		"res://audio/%s_music.ogg" % stem,
		"res://audio/%s_music.mp3" % stem,
		"res://audio/%s_music.wav" % stem,
		"res://audio/%s.wav" % stem,
	]:
		if ResourceLoader.exists(cand):
			path = cand
			break
	if path == "":
		return
	var s = load(path)
	if not (s is AudioStream):
		return
	var p := AudioStreamPlayer.new()
	p.stream = s
	p.process_mode = Node.PROCESS_MODE_ALWAYS   # survive the win-screen's tree pause
	p.volume_db = -2.0
	if AudioServer.get_bus_index(&"Music") != -1:
		p.bus = &"Music"
	add_child(p)
	p.play()

# Show the epic victory / defeat overlay (win_screen.gd). winner == 0 is the player.
func _show_win_banner(winner: int) -> void:
	var ws = WIN_SCREEN.new()
	ws.show_result(winner == 0)   # "YOU WIN" + hero, or a "DEFEAT" title
	add_child(ws)
