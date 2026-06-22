extends Node3D

const SFX := preload("res://scripts/sfx.gd")

@export var speed: float = 14.0
@export var hit_dist: float = 0.9

# UNTYPED cross-script state (duck-typed unit node with .alive, .global_position, .take_damage(amount))
var _target = null
var _dmg: float = 0.0
var _aim: Vector3 = Vector3.ZERO

var _visual: Node3D = null


func launch(from_pos: Vector3, target, dmg: float) -> void:
	global_position = from_pos
	_target = target
	_dmg = dmg
	if is_instance_valid(target):
		_aim = target.global_position


func _ready() -> void:
	SFX.play(self, "res://audio/fireball_launch", -10.0)
	if ResourceLoader.exists("res://models/fireball/fireball.glb"):
		var packed = load("res://models/fireball/fireball.glb")
		var inst = packed.instantiate()
		add_child(inst)
		inst.scale = Vector3(0.5, 0.5, 0.5)
		_visual = inst
	else:
		var mesh_inst := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.25
		sphere.height = 0.5
		mesh_inst.mesh = sphere

		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(1.0, 0.5, 0.1)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.45, 0.05)
		mat.emission_energy_multiplier = 3.0
		mesh_inst.material_override = mat
		add_child(mesh_inst)
		_visual = mesh_inst

		var light := OmniLight3D.new()
		light.light_color = Color(1.0, 0.5, 0.1)
		light.omni_range = 4.0
		light.light_energy = 2.0
		add_child(light)


func _process(delta: float) -> void:
	if is_instance_valid(_target) and _target.alive:
		_aim = _target.global_position + Vector3(0, 1.0, 0)

	var to = _aim - global_position
	var d = to.length()

	if d <= hit_dist:
		if is_instance_valid(_target) and _target.alive:
			_target.take_damage(_dmg)
		_impact()
		return

	global_position += (to / d) * speed * delta

	if is_instance_valid(_visual):
		_visual.rotate_y(delta * 8.0)


func _impact() -> void:
	SFX.play(self, "res://audio/fireball_impact", -10.0)
	set_process(false)
	var tw = create_tween()
	if tw:
		tw.set_parallel(true)
		tw.tween_property(self, "scale", scale * 1.6, 0.15)
		if is_instance_valid(_visual) and _visual is MeshInstance3D:
			var m = (_visual as MeshInstance3D).material_override
			if m is StandardMaterial3D:
				(_visual as MeshInstance3D).material_override = m.duplicate()
		tw.tween_callback(queue_free).set_delay(0.15)
	else:
		queue_free()
