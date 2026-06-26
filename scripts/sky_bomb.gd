extends Node3D
## A sudden-death bomb. Spawned high above the arena (a bit above the camera) by the
## battle manager, it falls straight down under gravity and, the instant it reaches
## the ground, calls back into the manager to detonate — an all-team AoE blast that
## hurts EVERYONE. Then it frees itself. Purely a falling visual; no targeting.

@export var gravity: float = 42.0      # downward accel (units/s^2)
@export var start_vel: float = 8.0     # initial downward speed

var _manager = null
var _vel: float = 0.0
var _done: bool = false

# Called by the manager AFTER add_child() + global_position (the spawn point) are set.
func setup(manager) -> void:
	_manager = manager
	_vel = start_vel
	_build()

func _build() -> void:
	var mi := MeshInstance3D.new()
	var sm := SphereMesh.new()
	sm.radius = 0.45
	sm.height = 0.9
	mi.mesh = sm
	var m := StandardMaterial3D.new()
	m.albedo_color = Color(0.07, 0.07, 0.08)   # dark iron bomb
	m.metallic = 0.5
	m.roughness = 0.4
	mi.material_override = m
	add_child(mi)
	# A small glowing fuse spark on top so it reads as a live bomb falling.
	var spark := MeshInstance3D.new()
	var ss := SphereMesh.new()
	ss.radius = 0.16
	ss.height = 0.32
	spark.mesh = ss
	var smat := StandardMaterial3D.new()
	smat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	smat.albedo_color = Color(1.0, 0.7, 0.2)
	spark.material_override = smat
	spark.position = Vector3(0.0, 0.5, 0.0)
	add_child(spark)

func _process(delta: float) -> void:
	if _done:
		return
	_vel += gravity * delta
	position.y -= _vel * delta
	if position.y <= 0.0:
		_done = true
		position.y = 0.0
		if is_instance_valid(_manager) and _manager.has_method("bomb_detonate"):
			_manager.bomb_detonate(global_position)
		queue_free()
