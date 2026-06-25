class_name Juice
extends RefCounted
## Global game-feel hub — static API callable from any script, no autoload (so no
## project reload needed). battle_manager registers the camera-shake provider and a
## live world node via Juice.setup() in _ready(). Every feel knob lives here.
##
## Design note for a swarm auto-battler: per-hit CAMERA shake is deliberately NOT
## fired on chip damage (dozens of hits/sec would shake the screen nonstop). Chip
## hits get local feedback (flash/squash/number/recoil, in hit_fx.gd); the camera
## only shakes + freezes on HEAVY hits and structure falls.

# --- Tuning -----------------------------------------------------------------
const HEAVY_HIT := 14.0          # damage at/above this counts as a "heavy" hit
const SHAKE_HEAVY := 0.40        # trauma added by a heavy hit
const HITSTOP_HEAVY := 0.05      # real seconds of freeze on a heavy hit
const HITSTOP_BOOM := 0.13       # real seconds of freeze on a structure fall
const TIME_FREEZE_SCALE := 0.05  # Engine.time_scale during a hitstop

static var _shake = null         # camera_pan.gd instance (has add_trauma)
static var _root: Node = null    # a live Node for spawning numbers/debris + timers
static var _hitstop_id := 0      # guards overlapping hitstops

# Called once by battle_manager._ready().
static func setup(shake_provider, root: Node) -> void:
	_shake = shake_provider
	_root = root

static func shake(amount: float) -> void:
	if _shake != null and is_instance_valid(_shake) and _shake.has_method("add_trauma"):
		_shake.add_trauma(amount)

# Brief global freeze-frame on a REAL-TIME timer, so it self-restores even with
# time_scale near zero. Overlapping calls extend the freeze; only the last one
# restores (id guard), so two quick heavy hits don't cut each other short.
static func hitstop(real_secs: float) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	var tree := _root.get_tree()
	if tree == null:
		return
	Engine.time_scale = TIME_FREEZE_SCALE
	_hitstop_id += 1
	var my_id := _hitstop_id
	var t := tree.create_timer(real_secs, true, false, true)  # ignore_time_scale = true
	t.timeout.connect(func() -> void:
		if my_id == _hitstop_id:
			Engine.time_scale = 1.0)

# A billboarded damage number that pops, arcs up and fades.
static func damage_number(world_pos: Vector3, amount: float, big: bool = false) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	var lbl := Label3D.new()
	lbl.text = str(int(round(amount)))
	lbl.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	lbl.no_depth_test = true
	lbl.fixed_size = true
	lbl.pixel_size = 0.0002 if not big else 0.000275
	lbl.font_size = 64
	lbl.modulate = Color(1.0, 0.95, 0.5) if not big else Color(1.0, 0.45, 0.2)
	lbl.outline_size = 14
	lbl.outline_modulate = Color(0, 0, 0, 0.85)
	lbl.render_priority = 6
	lbl.outline_render_priority = 5
	_root.add_child(lbl)
	# _root is a plain Node, so the Label3D has no parent transform: position == world.
	lbl.position = world_pos + Vector3(randf_range(-0.25, 0.25), 1.7, 0.0)
	var rise := 0.9 if not big else 1.3
	var dur := 0.6 if not big else 0.8
	var pop := Vector3.ONE * (1.0 if not big else 1.5)
	lbl.scale = pop * 0.5
	var t := lbl.create_tween()
	t.set_parallel(true)
	t.tween_property(lbl, "position:y", lbl.position.y + rise, dur).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "scale", pop, 0.16).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	t.tween_property(lbl, "modulate:a", 0.0, dur).set_ease(Tween.EASE_IN)
	t.set_parallel(false)
	t.tween_callback(lbl.queue_free)

# Big structure-fall payoff: strong shake + slow-mo + a debris/dust burst.
static func boom(world_pos: Vector3, strength: float = 1.0) -> void:
	shake(0.8 * strength)
	hitstop(HITSTOP_BOOM)
	_debris(world_pos, strength)

static func _debris(pos: Vector3, strength: float) -> void:
	if _root == null or not is_instance_valid(_root):
		return
	# Expanding additive dust ring.
	var ring := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.5
	sm.height = 1.0
	ring.mesh = sm
	var rm := StandardMaterial3D.new()
	rm.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rm.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rm.albedo_color = Color(1.0, 0.85, 0.5, 0.8)
	ring.material_override = rm
	_root.add_child(ring)
	ring.position = pos + Vector3(0, 1.0, 0)
	ring.scale = Vector3.ONE * 0.5
	var rt := ring.create_tween()
	rt.set_parallel(true)
	rt.tween_property(ring, "scale", Vector3.ONE * (5.0 * strength), 0.4).set_ease(Tween.EASE_OUT)
	rt.tween_property(rm, "albedo_color:a", 0.0, 0.4)
	rt.set_parallel(false)
	rt.tween_callback(ring.queue_free)
	# Chunky debris shards flung outward, arcing up then falling.
	var n := 10
	for i in n:
		var shard := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.25, 0.25, 0.25)
		shard.mesh = bm
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.55, 0.42, 0.3)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		shard.material_override = mat
		_root.add_child(shard)
		shard.position = pos + Vector3(0, 0.6, 0)
		shard.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var ang := TAU * float(i) / float(n)
		var outd := Vector3(cos(ang), 0, sin(ang))
		var apex := shard.position + outd * (2.5 * strength) + Vector3(0, randf_range(1.5, 3.0), 0)
		var land := Vector3(apex.x, 0.12, apex.z)
		var st := shard.create_tween()
		st.tween_property(shard, "position", apex, 0.45).set_ease(Tween.EASE_OUT)
		st.tween_property(shard, "position", land, 0.4).set_ease(Tween.EASE_IN)
		var ft := shard.create_tween()
		ft.tween_interval(0.6)
		ft.tween_property(mat, "albedo_color:a", 0.0, 0.3)
		ft.tween_callback(shard.queue_free)
