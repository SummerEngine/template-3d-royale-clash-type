extends SceneTree

const Catalog := preload("res://scripts/card_catalog.gd")
var _failures := 0

func _initialize() -> void:
	var directory := OS.get_environment("ROYAL_SKIN_TEST_DIRECTORY")
	if directory.is_empty():
		push_error("Set ROYAL_SKIN_TEST_DIRECTORY to an isolated writable directory")
		quit(1)
		return
	var path := directory.path_join("card-loadout-regression.cfg")
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	_expect(Catalog.load_loadout(path) == ["giant", "wizard", "barbarian"], "Fresh profile uses starter cards")
	var cfg := ConfigFile.new()
	cfg.set_value("audio", "music", 0.5)
	_expect(cfg.save(path) == OK, "Write audio-only profile")
	_expect(Catalog.load_loadout(path) == ["giant", "wizard", "barbarian"], "Audio-only profile uses starter cards")
	cfg.set_value("loadout", "cards", ["giant", "giant", "unknown"])
	_expect(cfg.save(path) == OK, "Write invalid loadout")
	_expect(Catalog.load_loadout(path) == ["giant", "wizard", "barbarian"], "Duplicate and unknown cards cannot create a loadout")
	cfg.set_value("loadout", "cards", ["barbarian", "giant", "wizard"])
	_expect(cfg.save(path) == OK, "Write selected loadout")
	_expect(Catalog.load_loadout(path) == ["barbarian", "giant", "wizard"], "Valid selection preserves slot order")
	var unchanged := ConfigFile.new()
	_expect(unchanged.load(path) == OK and unchanged.get_value("audio", "music", 0.0) == 0.5, "Reading cards preserves unrelated settings")
	DirAccess.remove_absolute(path)
	if _failures == 0:
		print("card_loadout: PASS")
	quit(0 if _failures == 0 else 1)

func _expect(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)
