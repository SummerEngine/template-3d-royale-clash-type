extends Node3D
# Freeze spell (Clash-Royale style). Targeted anywhere on the field; every enemy unit
# AND structure inside the circle is frozen solid for a few seconds — it stops moving,
# attacking and animating, encased in a block of ice — then thaws with a shatter. NOT
# a unit: the deploy controller free-aims it (spell mode) and the battle manager spawns
# it via cast_freeze(). Spends elixir through the normal try_deploy path.

@export var burst_time: float = 0.35

var _manager = null     # BattleManager — untyped for cross-script duck typing
var _team: int = 0
var _radius: float = 3.5
var _freeze_time: float = 3.5
var _frozen: Array = []   # [{node, anim, speed, ice}]

# Called by battle_manager.cast_freeze BEFORE add_child (so _ready has the values).
func setup(manager, team: int, radius: float, freeze_time: float) -> void:
	_manager = manager
	_team = team
	_radius = radius
	_freeze_time = freeze_time

func _ready() -> void:
	_telegraph()
	_burst_fx()
	_freeze_targets()
	await get_tree().create_timer(_freeze_time).timeout
	_unfreeze_all()
	await get_tree().create_timer(0.4).timeout
	if is_instance_valid(self):
		queue_free()

# --- Freeze logic ----------------------------------------------------------
func _freeze_targets() -> void:
	if _manager == null or not _manager.has_method("enemies_in_radius"):
		return
	for n in _manager.enemies_in_radius(global_position, _radius, _team):
		_freeze(n)

func _freeze(n) -> void:
	if not is_instance_valid(n):
		return
	n.set_meta("frozen", true)         # manager skips frozen units in separation/clamp
	n.set_process(false)               # stop its AI / movement / attacks
	n.set_physics_process(false)
	var ap := _find_anim(n)
	var prev_speed := 1.0
	if ap != null:
		prev_speed = ap.speed_scale
		ap.speed_scale = 0.0           # freeze the pose mid-stride
	var ice := _make_ice_block()
	n.add_child(ice)
	ice.scale = Vector3.ONE * 0.5
	ice.create_tween().tween_property(ice, "scale", Vector3.ONE, 0.16) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	_frozen.append({"node": n, "anim": ap, "speed": prev_speed, "ice": ice})

func _unfreeze_all() -> void:
	for f in _frozen:
		var n = f["node"]
		if is_instance_valid(n):
			n.remove_meta("frozen")
			n.set_process(true)
			n.set_physics_process(true)
			var ap = f["anim"]
			if ap != null and is_instance_valid(ap):
				ap.speed_scale = float(f["speed"]) if float(f["speed"]) > 0.0 else 1.0
		var ice = f["ice"]
		if is_instance_valid(ice):
			_shatter(ice)
	_frozen.clear()

# A translucent cyan ice block encasing a unit. Added as a child so it inherits the
# unit's scale (giants get a big block, skeletons a small one). Pops on, shatters off.
func _make_ice_block() -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(1.15, 1.7, 1.15)
	mi.mesh = box
	mi.position = Vector3(0.0, 0.85, 0.0)
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.6, 0.85, 1.0, 0.42)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.rim_enabled = true
	m.rim = 0.6
	m.metallic = 0.2
	m.roughness = 0.1
	m.emission_enabled = true
	m.emission = Color(0.4, 0.7, 1.0)
	m.emission_energy_multiplier = 0.25
	mi.material_override = m
	return mi

func _shatter(ice: MeshInstance3D) -> void:
	var m = ice.material_override
	var t := ice.create_tween()
	t.set_parallel(true)
	t.tween_property(ice, "scale", ice.scale * 1.3, 0.14).set_ease(Tween.EASE_OUT)
	if m is StandardMaterial3D:
		t.tween_property(m, "albedo_color:a", 0.0, 0.14)
	t.set_parallel(false)
	t.tween_callback(ice.queue_free)

# --- FX --------------------------------------------------------------------
# Cyan ground ring + a faint frosty dome marking the frozen zone for the duration.
func _telegraph() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.outer_radius = _radius
	torus.inner_radius = maxf(0.3, _radius - 0.3)
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.45, 0.8, 1.0, 0.75)
	m.no_depth_test = true
	ring.material_override = m
	add_child(ring)
	ring.position = Vector3(0.0, 0.06, 0.0)
	ring.create_tween().tween_property(m, "albedo_color:a", 0.0, 0.5).set_delay(_freeze_time)

	var dome := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = _radius
	sph.height = _radius * 2.0
	dome.mesh = sph
	var dm := StandardMaterial3D.new()
	dm.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	dm.albedo_color = Color(0.6, 0.85, 1.0, 0.12)
	dm.rim_enabled = true
	dm.rim = 0.5
	dm.cull_mode = BaseMaterial3D.CULL_DISABLED
	dome.material_override = dm
	add_child(dome)
	dome.position = Vector3(0.0, 0.1, 0.0)
	dome.scale = Vector3(1.0, 0.55, 1.0)   # flatten the sphere into a dome
	dome.create_tween().tween_property(dm, "albedo_color:a", 0.0, 0.5).set_delay(_freeze_time)

# A bright frost flash + a spray of ice shards at the moment of casting.
func _burst_fx() -> void:
	var flash := MeshInstance3D.new()
	var sph := SphereMesh.new()
	sph.radius = 1.0
	sph.height = 2.0
	flash.mesh = sph
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.albedo_color = Color(0.6, 0.9, 1.0, 0.9)
	flash.material_override = m
	add_child(flash)
	flash.position = Vector3(0.0, 0.8, 0.0)
	flash.scale = Vector3.ONE * 0.4
	var t := flash.create_tween()
	t.set_parallel(true)
	t.tween_property(flash, "scale", Vector3.ONE * (_radius * 1.2), burst_time).set_ease(Tween.EASE_OUT)
	t.tween_property(m, "albedo_color:a", 0.0, burst_time).set_ease(Tween.EASE_IN)
	t.set_parallel(false)
	t.tween_callback(flash.queue_free)

	for i in 10:
		var shard := MeshInstance3D.new()
		var bm := BoxMesh.new()
		bm.size = Vector3(0.18, 0.18, 0.18)
		shard.mesh = bm
		var sm := StandardMaterial3D.new()
		sm.albedo_color = Color(0.7, 0.9, 1.0)
		sm.emission_enabled = true
		sm.emission = Color(0.5, 0.8, 1.0)
		sm.emission_energy_multiplier = 0.4
		shard.material_override = sm
		add_child(shard)
		shard.position = Vector3(0.0, 0.4, 0.0)
		shard.rotation = Vector3(randf() * TAU, randf() * TAU, randf() * TAU)
		var ang := TAU * float(i) / 10.0
		var apex := shard.position + Vector3(cos(ang), 0, sin(ang)) * (_radius * 0.9) + Vector3(0, randf_range(0.5, 1.5), 0)
		var land := Vector3(apex.x, 0.06, apex.z)
		var st := shard.create_tween()
		st.tween_property(shard, "position", apex, 0.25).set_ease(Tween.EASE_OUT)
		st.tween_property(shard, "position", land, 0.3).set_ease(Tween.EASE_IN)
		st.tween_callback(shard.queue_free)

func _find_anim(n) -> AnimationPlayer:
	if n is AnimationPlayer:
		return n
	for c in n.get_children():
		var f := _find_anim(c)
		if f != null:
			return f
	return null
