extends RefCounted
## Local preference policy. Ownership is supplied only from the live SDK projection.
const STYLES := ["default", "gilded", "emerald"]
var account := ""
var game := ""
var selected := "default"
var owned: Array[String] = []

func bind(user_id: String, game_id: String, preference: String) -> void:
	account = user_id
	game = game_id
	owned.clear()
	selected = preference if preference in STYLES else "default"

func reconcile(definitions: Array[String], loaded: bool, bindings: Dictionary) -> void:
	owned.clear()
	if loaded and not account.is_empty() and not game.is_empty():
		for style in ["gilded", "emerald"]:
			var definition := str(bindings.get(style, ""))
			if not definition.is_empty() and definition in definitions:
				owned.append(style)
	if selected != "default" and selected not in owned:
		selected = "default"

func equip(style: String) -> bool:
	if style != "default" and style not in owned:
		return false
	selected = style
	return true

func preference_section() -> String:
	# Hash separately: no account identifiers in configuration section names.
	return "keep_skin/" + game.sha256_text() + "/" + account.sha256_text()

func save_preference(path: String = "user://keep_skins.cfg") -> Error:
	if account.is_empty() or game.is_empty():
		return ERR_UNAUTHORIZED
	var cfg := ConfigFile.new()
	var result := cfg.load(path)
	if result != OK and result != ERR_FILE_NOT_FOUND:
		return result
	cfg.set_value(preference_section(), "selected", selected)
	return cfg.save(path)

func load_preference(path: String = "user://keep_skins.cfg") -> void:
	var cfg := ConfigFile.new()
	cfg.load(path)
	selected = str(cfg.get_value(preference_section(), "selected", "default"))
