# Reusable "juicy hit" feedback fired from a unit/base take_damage():
#   1) a bright white flash on the hit mesh,
#   2) a squash-stretch scale pop on the body,
#   3) a quick additive impact spark that expands and fades.
# Call: HitFx.play(self, _find_mesh_instance(self), Vector3.ONE * visual_scale)
extends RefCounted

static func play(body: Node3D, mesh: MeshInstance3D, base_scale: Vector3, pop: bool = true) -> void:
	if not is_instance_valid(body):
		return

	# 1) Bright white flash on the hit body's mesh (~0.07s), then restore.
	if is_instance_valid(mesh):
		var fm := StandardMaterial3D.new()
		fm.albedo_color = Color(1, 1, 1)
		fm.emission_enabled = true
		fm.emission = Color(1, 1, 1)
		fm.emission_energy_multiplier = 2.5
		mesh.material_override = fm
		var t := body.create_tween()
		t.tween_interval(0.07)
		t.tween_callback(func() -> void:
			if is_instance_valid(mesh):
				mesh.material_override = null)

	# 2) Squash-stretch pop on the whole body.
	if pop:
		var t2 := body.create_tween()
		t2.tween_property(body, "scale", base_scale * 1.22, 0.05).set_ease(Tween.EASE_OUT)
		t2.tween_property(body, "scale", base_scale, 0.14).set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)

	# 3) Impact spark: a quick additive sphere that expands and fades. Parented to
	#    the body's parent (world space) so it doesn't inherit the body's scale/pop.
	var parent := body.get_parent()
	if parent != null:
		var spark := MeshInstance3D.new()
		var sm := SphereMesh.new()
		sm.radius = 0.22
		sm.height = 0.44
		spark.mesh = sm
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		mat.albedo_color = Color(1.0, 0.9, 0.55, 0.9)
		spark.material_override = mat
		parent.add_child(spark)
		spark.global_position = body.global_position + Vector3(0.0, 1.2, 0.0)
		spark.scale = Vector3.ONE * 0.4
		var t3 := spark.create_tween().set_parallel(true)
		t3.tween_property(spark, "scale", Vector3.ONE * 2.4, 0.18).set_ease(Tween.EASE_OUT)
		t3.tween_property(mat, "albedo_color:a", 0.0, 0.18).set_ease(Tween.EASE_IN)
		t3.chain().tween_callback(spark.queue_free)
