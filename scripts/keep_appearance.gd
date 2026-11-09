extends RefCounted
## Duplicate surface materials, preserving the original textures and team overlay.
## No mesh, collision, hit point, targeting, or combat changes.
var _surfaces: Array = []

func capture(root: Node) -> void:
	if root is MeshInstance3D and root.mesh != null:
		for index in root.mesh.get_surface_count():
			var original = root.get_active_material(index)
			if original is StandardMaterial3D:
				_surfaces.append([root, index, original])
	for child in root.get_children():
		capture(child)

func apply(style: String) -> void:
	for surface in _surfaces:
		var mesh: MeshInstance3D = surface[0]
		var original: StandardMaterial3D = surface[2]
		if style == "default":
			mesh.set_surface_override_material(surface[1], original)
			continue
		var material: StandardMaterial3D = original.duplicate()
		material.albedo_color = original.albedo_color * (Color(1.0, 0.78, 0.36) if style == "gilded" else Color(0.35, 0.95, 0.65))
		material.metallic = 0.45 if style == "gilded" else 0.15
		material.roughness = 0.38
		mesh.set_surface_override_material(surface[1], material)
