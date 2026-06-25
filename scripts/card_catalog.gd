extends RefCounted
## Single source of truth for every spawnable card in the game.
##
## To add a new unit type to the hotbar: add ONE entry to all(). It then shows up
## in the loadout collection and becomes selectable for the in-match buttons
## automatically — no other file needs editing. UI data (name/texture) and gameplay
## data (cost / glb / script / drag-ghost scale) live together here.
##
## GLB and script are stored as PATHS and loaded lazily (only the battle scene
## load()s them), so the menu can show the collection without pulling the heavy
## character models into memory.

const SETTINGS_PATH := "user://settings.cfg"
const DEFAULT_LOADOUT := ["barbarian", "wizard", "builder"]

# Every card the game knows about. Order = collection display order.
static func all() -> Array:
	return [
		{
			"id": "barbarian", "name": "Barbarian",
			"texture": "res://ui/barbarian_button.png", "cost": 2.0, "scale": 1.3,
			"glb": "res://models/viking/Meshy_AI_Viking_Action_Figure__biped_Animation_Walking_withSkin.glb",
			"script": "res://scripts/barbarian.gd",
		},
		{
			"id": "wizard", "name": "Wizard",
			"texture": "res://ui/wizard_button.png", "cost": 3.0, "scale": 1.3,
			"glb": "res://models/wizard/Meshy_AI_Violet_Archmage_biped_Animation_Walking_withSkin.glb",
			"script": "res://scripts/wizard.gd",
		},
		{
			"id": "builder", "name": "Builder",
			"texture": "res://ui/builder_button.png", "cost": 4.0, "scale": 1.3,
			"glb": "res://models/dwarf/Meshy_AI_Flying_Dwarf_biped_Animation_Walking_withSkin.glb",
			"script": "res://scripts/builder.gd",
		},
		{
			# Giant: huge, slow, very tanky — only attacks buildings. The card's "scale"
			# is only the drag-ghost preview size; the unit sets its own big visual_scale.
			"id": "giant", "name": "Giant",
			"texture": "res://ui/giant_button.png", "cost": 4.0, "scale": 2.0,
			"glb": "res://models/giant/Meshy_AI_Barbarian_Behemoth_biped_Animation_Walking_withSkin.glb",
			"script": "res://scripts/giant.gd",
		},
		{
			# Bomber: fast, fragile suicide unit — jumps and explodes for big AoE.
			"id": "bomber", "name": "Bomber",
			"texture": "res://ui/skeleton_button.png", "cost": 2.0, "scale": 1.3,
			"glb": "res://models/skeleton/Meshy_AI_Bomb_Carrying_Skeleto_biped_Animation_Walking_withSkin.glb",
			"script": "res://scripts/bomber.gd",
		},
	]

static func by_id(id: String) -> Dictionary:
	for c in all():
		if c["id"] == id:
			return c
	return {}

# The 3 chosen card ids in slot order, validated to be known + distinct. Falls back
# to the default trio if the saved value is missing or malformed.
static func load_loadout() -> Array:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var raw = cfg.get_value("loadout", "cards", null)
	var out: Array = []
	if raw is Array:
		for v in raw:
			var id := str(v)
			if not by_id(id).is_empty() and not out.has(id):
				out.append(id)
	if out.size() != 3:
		return DEFAULT_LOADOUT.duplicate()
	return out

static func save_loadout(ids: Array) -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)   # keep the [audio] section intact
	cfg.set_value("loadout", "cards", ids)
	cfg.save(SETTINGS_PATH)

# Robust texture load: prefer the imported resource, fall back to a raw image read
# so it works even before Godot has imported the PNG (same pattern as the HUD).
static func load_texture(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is Texture2D:
			return res
	var img := Image.new()
	if img.load(path) == OK:
		return ImageTexture.create_from_image(img)
	return null
