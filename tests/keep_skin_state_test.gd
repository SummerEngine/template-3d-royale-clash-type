extends SceneTree
var _failures := 0

const State := preload("res://scripts/keep_skin_state.gd")

func _initialize() -> void:
	var state = State.new()
	var bindings := {"gilded": "definition-a", "emerald": "definition-b"}
	state.bind("alice", "game-a", "gilded")
	state.reconcile([], false, bindings)
	_expect(state.selected == "default", "Saved choice is not entitlement")
	_expect(not state.equip("gilded"), "A checkout receipt alone cannot equip")
	var owned: Array[String] = ["definition-a"]
	state.reconcile(owned, true, bindings)
	_expect(state.equip("gilded"))
	_expect(not state.equip("emerald"), "One owned skin cannot unlock another")
	var alice_section: String = state.preference_section()
	state.bind("bob", "game-a", "gilded")
	state.reconcile([], true, bindings)
	_expect(state.selected == "default" and state.preference_section() != alice_section)
	state.bind("alice", "game-b", "gilded")
	_expect(state.preference_section() != alice_section, "Games have separate preferences")
	state.bind("alice", "game-a", "gilded")
	state.reconcile(owned, true, bindings)
	_expect(state.selected == "gilded")
	state.reconcile([], true, bindings)
	_expect(state.selected == "default", "Revocation immediately removes appearance")
	state.reconcile(owned, true, {"gilded": "", "emerald": ""})
	_expect(not state.equip("gilded"), "An unpublished mapping grants nothing")
	_expect(state.equip("default"))
	_check_preferences()
	_check_materials()
	if _failures == 0:
		print("keep_skin_state and appearance: PASS")
	quit(0 if _failures == 0 else 1)

func _check_materials() -> void:
	var root := Node3D.new()
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	mesh.mesh = box
	var original := StandardMaterial3D.new()
	original.albedo_color = Color(0.8, 0.7, 0.6)
	box.material = original
	var team_overlay := StandardMaterial3D.new()
	mesh.material_overlay = team_overlay
	root.add_child(mesh)
	var appearance = preload("res://scripts/keep_appearance.gd").new()
	appearance.capture(root)
	var geometry: Mesh = mesh.mesh
	appearance.apply("gilded")
	var gold: StandardMaterial3D = mesh.get_active_material(0)
	_expect(gold != original and original.albedo_color == Color(0.8, 0.7, 0.6))
	_expect(mesh.mesh == geometry and mesh.material_overlay == team_overlay)
	appearance.apply("emerald")
	var green: StandardMaterial3D = mesh.get_active_material(0)
	_expect(green.albedo_color != gold.albedo_color)
	appearance.apply("default")
	_expect(mesh.get_active_material(0) == original and mesh.material_overlay == team_overlay)
	root.free()

func _check_preferences() -> void:
	var test_root := OS.get_environment("ROYAL_SKIN_TEST_DIRECTORY")
	if test_root.is_empty():
		_expect(false, "Set ROYAL_SKIN_TEST_DIRECTORY to an isolated writable directory")
		return
	var directory := test_root.path_join("royal-skins-test-" + str(Time.get_ticks_usec()))
	_expect(DirAccess.make_dir_recursive_absolute(directory) == OK)
	var skins_path := directory.path_join("keep_skins.cfg")
	var audio_path := directory.path_join("settings.cfg")
	var state = State.new()
	state.bind("alice", "game-a", "default")
	var definitions: Array[String] = ["owned-definition"]
	state.reconcile(definitions, true, {"gilded": "owned-definition"})
	_expect(state.equip("gilded"))
	_expect(state.save_preference(skins_path) == OK)
	# Existing audio preferences legitimately rewrite their own file.
	var audio := ConfigFile.new()
	audio.set_value("audio", "music", 0.5)
	_expect(audio.save(audio_path) == OK)
	var restarted = State.new()
	restarted.bind("alice", "game-a", "default")
	restarted.load_preference(skins_path)
	restarted.reconcile(definitions, true, {"gilded": "owned-definition"})
	_expect(restarted.selected == "gilded", "Audio saves must not erase skin selection")
	restarted.bind("bob", "game-a", "default")
	restarted.load_preference(skins_path)
	_expect(restarted.selected == "default")
	DirAccess.remove_absolute(skins_path)
	DirAccess.remove_absolute(audio_path)
	DirAccess.remove_absolute(directory)

func _expect(condition: bool, message: String = "Behavioral assertion failed") -> void:
	if not condition:
		_failures += 1
		push_error(message)
