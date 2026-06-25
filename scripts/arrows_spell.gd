extends Node3D
# Arrows spell (Clash-Royale style). A volley rains down over a circular area, then
# deals ONE burst of AoE damage to every enemy unit + structure in radius. It is NOT
# a unit — the deploy controller aims it anywhere on the field (spell mode) and the
# battle manager spawns it via cast_arrows(). Spends elixir through the normal
# try_deploy path, so afford/reject feedback is free.

@export var fall_time: float = 0.42     # seconds an arrow takes to drop
@export var hit_delay: float = 0.5      # when the damage lands (~ when the arrows hit ground)
@export var arrow_count: int = 16       # arrows in the volley
@export var spawn_height: float = 18.0   # how high arrows start above the target
@export var damage_radius_bonus: float = 1.5   # damage reaches this far PAST the red ring. Hits are measured to a unit's CENTER, so units whose bodies overlap the rim (center just outside) were surviving and the ring looked oversold — this buffs the real hit range to cover and beat the circle.

var _manager = null     # BattleManager — untyped for cross-script duck typing
var _team: int = 0
var _radius: float = 4.0
var _damage: float = 30.0

# Called by battle_manager.cast_arrows BEFORE add_child (so _ready has the values).
func setup(manager, team: int, radius: float, damage: float) -> void:
	_manager = manager
	_team = team
	_radius = radius
	_damage = damage

func _ready() -> void:
	_telegraph()
	_spawn_arrows()
	await get_tree().create_timer(hit_delay).timeout
	if is_instance_valid(_manager) and _manager.has_method("explode_damage"):
		# Hit a bit past the telegraph ring so units overlapping the rim are actually
		# caught (the center-based check made the red circle look oversold).
		_manager.explode_damage(global_position, _radius + damage_radius_bonus, _damage, _team)
	# Let the last arrows + ring finish, then clean up.
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(self):
		queue_free()

# Flat red ground ring marking the struck area; fades out shortly after impact.
func _telegraph() -> void:
	var ring := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.outer_radius = _radius
	torus.inner_radius = maxf(0.3, _radius - 0.3)
	ring.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.albedo_color = Color(0.95, 0.32, 0.2, 0.7)
	m.no_depth_test = true
	ring.material_override = m
	add_child(ring)
	ring.position = Vector3(0.0, 0.06, 0.0)
	ring.create_tween().tween_property(m, "albedo_color:a", 0.0, hit_delay + 0.4).set_delay(0.1)

# A staggered volley: each arrow starts high over a random point in the disc and
# drops point-first to the ground, sticks for a beat, then shrinks away.
func _spawn_arrows() -> void:
	# Real low-poly arrow model. load() at runtime (not preload) like the other
	# freshly-generated GLBs, so this still parses before the asset is imported;
	# falls back to a procedural point-down spike if the model is missing.
	var arrow_scene = load("res://models/arrow.glb")
	for i in arrow_count:
		# Slight lean + random yaw so the volley reads as raining arrows, not a grid.
		var tilt := deg_to_rad(12.0 + randf() * 10.0)
		var yaw := randf() * TAU
		var arrow
		if arrow_scene != null:
			arrow = arrow_scene.instantiate()
			# Model long axis is +X with the head toward -X. Rotate +90° about Z so the
			# head points straight down (-Y), then apply the yaw (about up) and lean
			# (about X). Scale the ~1.18u model to ~1.2u tall.
			var r := Basis(Vector3(1, 0, 0), tilt) * Basis(Vector3.UP, yaw) * Basis(Vector3(0, 0, 1), PI / 2.0)
			arrow.transform = Transform3D(r.scaled(Vector3.ONE * 1.0), Vector3.ZERO)
		else:
			arrow = _make_spike()
			# Cylinder is Y-up with its point already at -Y; just lean + yaw it.
			arrow.rotation = Vector3(tilt, yaw, 0.0)
		add_child(arrow)
		# Uniform random landing spot within the radius (sqrt for even disc coverage).
		var ang := randf() * TAU
		var rr := sqrt(randf()) * _radius
		arrow.position = Vector3(cos(ang) * rr, spawn_height + randf() * 6.0, sin(ang) * rr)
		var tw = arrow.create_tween()
		tw.tween_interval(randf() * 0.18)
		tw.tween_property(arrow, "position:y", 0.05, fall_time).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_IN)
		tw.tween_interval(0.22)
		tw.tween_property(arrow, "scale", Vector3.ZERO, 0.15)

# Procedural fallback arrow: a Y-up cylinder tapered to a downward point.
func _make_spike() -> MeshInstance3D:
	var arrow := MeshInstance3D.new()
	var spike := CylinderMesh.new()
	spike.top_radius = 0.14          # shaft
	spike.bottom_radius = 0.0        # pointed tip (downward)
	spike.height = 1.7
	arrow.mesh = spike
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.45, 0.32, 0.16)   # wooden shaft
	arrow.material_override = mat
	return arrow
