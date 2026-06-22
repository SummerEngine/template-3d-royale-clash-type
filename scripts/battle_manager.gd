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
const ELIXIR := preload("res://scripts/elixir.gd")
const ELIXIR_UI := preload("res://scripts/elixir_ui.gd")
const SFX := preload("res://scripts/sfx.gd")
const SPAWN_CARD := preload("res://scripts/spawn_card.gd")
const HOUSE_BAR := preload("res://scripts/house_health_bar.gd")
const HOUSE_HUD := preload("res://scripts/house_hud.gd")
const CAMERA_PAN := preload("res://scripts/camera_pan.gd")
const DEPLOY_CONTROLLER := preload("res://scripts/deploy_controller.gd")
const WIN_SCREEN := preload("res://scripts/win_screen.gd")

@export var player_base_path: NodePath
@export var enemy_base_path: NodePath
@export var squad_size: int = 10
@export var wizard_count: int = 3   # ranged wizards per team, spawned behind the front line
@export var builder_count: int = 2   # non-combat builders per team, spawned behind the line
@export var separation_strength: float = 0.5   # fraction of overlap resolved per physics frame (0..1); soft push
@export var island_half_extent: float = 19.0
@export var island_octagon_limit: float = 31.0   # |x|+|z| bound; diagonal arena walls sit at 32, units inset 1
@export var moat_half_width: float = 1.5     # perpendicular half-width of the real grass gap (slab inner edges at +/-1.5)
@export var bridge_offset: float = 9.0       # each bridge sits this far from centre along the moat
@export var bridge_half_width: float = 2.6   # half the crossable gap at each bridge
@export var bridge_capture: float = 2.0      # if shoved this far past a bridge edge (still in water), slide back onto the bridge instead of off it
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
@export var builder_spawn_cost: float = 3.0      # elixir cost per builder

const SPAWN_CARD_GAP := 48.0   # px gap between spawn cards (clears both glow halos)

# Central moat geometry: it runs along the x+z=0 diagonal (perpendicular to the
# blue->red battle axis). MOAT_N points across it (the battle axis), MOAT_T along it.
const MOAT_N := Vector3(0.70710678, 0, 0.70710678)   # unit normal across the moat
const MOAT_T := Vector3(0.70710678, 0, -0.70710678)  # unit tangent along the moat

var units: Array = [[], []]   # units[0] = team 0 list, units[1] = team 1 list (Arrays of unit Node3Ds)
var _pumps: Array = []        # built structures: { "node": Node3D, "r": float } — units get shoved out, pumps never move
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

	# Spawn both squads, each clustered in front of its own base.
	spawn_squad(0, _player_base, _enemy_base)
	spawn_squad(1, _enemy_base, _player_base)

	# SFX players, then the elixir economy/HUD (cards read its afford state on
	# build), then the player spawn cards, then the enemy auto-spawn.
	_setup_audio()
	_setup_elixir()
	_build_spawn_cards()
	_start_enemy_spawner()

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
func spawn_squad(team: int, own_base: Node3D, enemy_base: Node3D) -> void:
	# Direction from the base toward the origin (map center).
	var to_center := Vector3.ZERO - own_base.global_position
	to_center.y = 0.0
	var dir := to_center.normalized()
	var cluster_center := own_base.global_position + dir * 5.0
	cluster_center.y = 0.0

	# Scatter each unit around the cluster center with a per-index jitter
	# so they don't perfectly overlap.
	for i in squad_size:
		var offset := Vector3(
			randf_range(-3.0, 3.0),
			0.0,
			randf_range(-3.0, 3.0)
		)
		var spawn_pos := cluster_center + offset
		spawn_pos.y = 0.0
		_make_unit(team, enemy_base, spawn_pos)

	# A few ranged wizards behind the front line (closer to own base).
	var wiz_center := own_base.global_position + dir * 2.5
	wiz_center.y = 0.0
	for i in wizard_count:
		var w_offset := Vector3(randf_range(-2.5, 2.5), 0.0, randf_range(-2.5, 2.5))
		var w_pos := wiz_center + w_offset
		w_pos.y = 0.0
		_make_wizard(team, enemy_base, w_pos)

	# A couple of non-combat builders behind the line; they plant and "build".
	for i in builder_count:
		var b_offset := Vector3(randf_range(-2.0, 2.0), 0.0, randf_range(-2.0, 2.0))
		var b_pos := wiz_center + b_offset
		b_pos.y = 0.0
		_make_builder(team, enemy_base, b_pos)

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
	return MOAT_T * b_along

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
	# Gather all alive, valid units across both teams.
	var all: Array = []
	for team_list in units:
		for u in team_list:
			if is_instance_valid(u) and u.alive:
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
# Three SpawnCard slots in a row (right -> left): barbarian (costs 1), wizard
# (costs 2), builder (costs 2). Each card owns its glow halo, press juice, and
# afford pulse; the gameplay (afford/spend/spawn) stays here via the callbacks.
func _build_spawn_cards() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)

	var barb_tex := _load_texture("res://ui/barbarian_button.png")
	var wiz_tex := _load_texture("res://ui/wizard_button.png")
	var builder_tex := _load_texture("res://ui/builder_button.png")
	var drop_tex := _load_texture("res://ui/elixir_drop.png")

	# One shared drag-to-deploy controller (owns the ghost, placement, commit).
	var deploy = DEPLOY_CONTROLLER.new()
	deploy.bind(self, get_viewport().get_camera_3d(), _player_base, _cam_pan)
	add_child(deploy)

	# All three cards use drop-free art, so each overlays its cost as drops:
	# barbarian 1, wizard 2, builder 2. On press each hands the controller a
	# unit_def: the model for the ghost + a positional spawn fn.
	var barb := SPAWN_CARD.new()
	layer.add_child(barb)
	_place_card(barb, 0)   # slot 0 = rightmost corner
	barb.setup(spawn_button_size, barb_tex, spawn_cost, int(spawn_cost), drop_tex, _elixir, deploy,
		{ "glb": UNIT_GLB, "scale": 1.3, "spawn_fn": spawn_one_at })

	var wiz := SPAWN_CARD.new()
	layer.add_child(wiz)
	_place_card(wiz, 1)    # slot 1 = one step to the left
	wiz.setup(spawn_button_size, wiz_tex, wizard_spawn_cost, int(wizard_spawn_cost), drop_tex, _elixir, deploy,
		{ "glb": WIZARD_GLB, "scale": 1.3, "spawn_fn": spawn_one_wizard_at })

	var builder := SPAWN_CARD.new()
	layer.add_child(builder)
	_place_card(builder, 2)   # slot 2 = leftmost
	builder.setup(spawn_button_size, builder_tex, builder_spawn_cost, int(builder_spawn_cost), drop_tex, _elixir, deploy,
		{ "glb": BUILDER_GLB, "scale": 1.3, "spawn_fn": spawn_one_builder_at })

# Pin a card to the bottom-right corner, stepping `slot` cards to the left.
func _place_card(card: Control, slot: int) -> void:
	card.set_anchors_preset(Control.PRESET_BOTTOM_RIGHT)
	var right := -spawn_button_margin - float(slot) * (spawn_button_size + SPAWN_CARD_GAP)
	card.offset_right = right
	card.offset_left = right - spawn_button_size
	card.offset_bottom = -spawn_button_margin
	card.offset_top = -spawn_button_margin - spawn_button_size

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

# --- SFX players -----------------------------------------------------------
func _setup_audio() -> void:
	# The generator padded both clips to ~1s; trim them to a snappy UI length.
	_sfx_spawn = _make_sfx("res://audio/spawn_pop.wav", -14.0, 0.22)
	_sfx_denied = _make_sfx("res://audio/spawn_denied.wav", -2.0, 0.16)
	_setup_music()

# Constant looping battle music, routed through the Music bus (slider-controlled).
func _setup_music() -> void:
	var path := "res://audio/battle_music.wav"
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

	var hud = HOUSE_HUD.new()
	hud.bind(_player_base, _enemy_base)
	add_child(hud)

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
	# affordable, so e.g. a 4-cost builder rolled at 3 just banks toward 4 instead of
	# spawning for free.
	var r := randf()
	if r < enemy_barb_chance:
		if _enemy_elixir.spend(spawn_cost):
			spawn_one(1, _enemy_base, _player_base)
	elif r < enemy_barb_chance + enemy_wizard_chance:
		if _enemy_elixir.spend(wizard_spawn_cost):
			spawn_one_wizard(1, _enemy_base, _player_base)
	else:
		if _enemy_elixir.spend(builder_spawn_cost):
			spawn_one_builder(1, _enemy_base, _player_base)

# A base was destroyed: its team loses, the other team wins. Show it once.
func _on_base_destroyed(team: int) -> void:
	if _winner_shown:
		return
	_winner_shown = true
	var winner := 1 - team
	SFX.play(self, "res://audio/victory" if winner == 0 else "res://audio/defeat", 2.0)
	_show_win_banner(winner)

# Show the epic victory / defeat overlay (win_screen.gd). winner == 0 is the player.
func _show_win_banner(winner: int) -> void:
	var ws = WIN_SCREEN.new()
	ws.show_result(winner == 0)   # "YOU WIN" + hero, or a "DEFEAT" title
	add_child(ws)
