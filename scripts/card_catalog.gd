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
const DEFAULT_LOADOUT := ["giant", "wizard", "barbarian"]

# --- Unlocks / gold --------------------------------------------------------
const UNLOCK_COST := 100                          # gold to unlock a locked card
const LOCKED_DEFAULT := ["builder", "arrows", "archer_tower", "freeze"]   # cards that start locked
# Meeting-demo reset: on each app launch, relock the default-locked cards and refill
# gold to DEMO_START_GOLD, so every tester starts fresh and can unlock + try them.
# Set DEMO_RESET=false to restore the persistent economy (earned coins + permanent
# unlocks that carry across launches).
const DEMO_RESET := false
const DEMO_START_GOLD := 250

# Guarded by a static flag: resets on app restart but survives menu<->match scene
# changes within a session, so the demo reset runs once per launch (not per menu visit).
static var _session_inited := false

# Call once at app entry (menu _ready). With DEMO_RESET on, relocks the default cards
# and tops gold up so testers always start able to unlock both.
static func ensure_session() -> void:
	if _session_inited:
		return
	_session_inited = true
	if not DEMO_RESET:
		return
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("unlocks", "ids", [])              # relock everything default-locked
	cfg.set_value("profile", "coins", DEMO_START_GOLD)
	cfg.save(SETTINGS_PATH)

# Relock every default-locked card (clears the saved unlocks) so the unlock flow can
# be shown off again. Does not touch gold.
static func relock_all() -> void:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("unlocks", "ids", [])
	cfg.save(SETTINGS_PATH)

static func unlocked_ids() -> Array:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var raw = cfg.get_value("unlocks", "ids", [])
	return raw if raw is Array else []

# A card is locked if it's default-locked AND not yet purchased this session.
static func is_locked(id: String) -> bool:
	if not LOCKED_DEFAULT.has(id):
		return false
	return not unlocked_ids().has(id)

# Gold price to unlock a card — per-card "unlock_cost" if set, else the default.
# Change a card's price by editing its "unlock_cost" in all() above.
static func unlock_cost(id: String) -> int:
	return int(by_id(id).get("unlock_cost", UNLOCK_COST))

# Spend gold to unlock `id`. Returns true if it's now unlocked (or already was),
# false if the player can't afford it.
static func try_unlock(id: String) -> bool:
	if not is_locked(id):
		return true
	var cost := unlock_cost(id)
	if Profile.get_coins() < cost:
		return false
	Profile.add_coins(-cost)
	var ids := unlocked_ids()
	ids.append(id)
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("unlocks", "ids", ids)
	cfg.save(SETTINGS_PATH)
	return true

# --- Levels / upgrades -----------------------------------------------------
const UPGRADE_BASE := 100         # gold for level 1->2; scales by current level (100, 200, 300...)
const LEVEL_STAT_STEP := 0.15     # +15% HP & damage per level above 1

static func get_level(id: String) -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return maxi(1, int(cfg.get_value("levels", id, 1)))

# Gold to go from the current level to the next.
static func upgrade_cost(id: String) -> int:
	return UPGRADE_BASE * get_level(id)

# Stat multiplier applied to this card's spawned units (1.0 at level 1).
static func level_multiplier(id: String) -> float:
	return 1.0 + LEVEL_STAT_STEP * float(get_level(id) - 1)

# Spend gold to raise `id` one level. Returns the NEW level, or 0 if unaffordable.
static func try_upgrade(id: String) -> int:
	var cost := upgrade_cost(id)
	if Profile.get_coins() < cost:
		return 0
	Profile.add_coins(-cost)
	var lvl := get_level(id) + 1
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	cfg.set_value("levels", id, lvl)
	cfg.save(SETTINGS_PATH)
	return lvl


# Every card the game knows about. Order = collection display order.
static func all() -> Array:
	return [
		{
			"id": "barbarian", "name": "Barbarian",
			"texture": "res://ui/barbarian_button.png", "cost": 2.0, "scale": 1.3,
			"glb": "res://models/viking/viking_walk.glb",
			"script": "res://scripts/barbarian.gd",
			"flavor": "A reckless brute who charges the nearest enemy and swings until it drops. Cheap, sturdy, and always hungry for a fight.",
			"stats": [["Role", "Melee"], ["Health", "40"], ["Damage", "8"], ["Hit speed", "1.1s"], ["Move speed", "Medium"]],
			"level_stats": ["Health", "Damage"],
		},
		{
			"id": "wizard", "name": "Wizard",
			"texture": "res://ui/wizard_button.png", "cost": 3.0, "scale": 1.3,
			"glb": "res://models/wizard/wizard_walk.glb",
			"script": "res://scripts/wizard.gd",
			"flavor": "Rains fireballs from afar. Devastating at range, but fragile — keep him behind the front line.",
			"stats": [["Role", "Ranged"], ["Health", "26"], ["Damage", "12"], ["Range", "8"], ["Move speed", "Medium"]],
			"level_stats": ["Health", "Damage"],
		},
		{
			# Giant: huge, slow, very tanky — only attacks buildings. The card's "scale"
			# is only the drag-ghost preview size; the unit sets its own big visual_scale.
			"id": "giant", "name": "Giant",
			"texture": "res://ui/giant_button.png", "cost": 4.0, "scale": 2.0,
			"glb": "res://models/giant/giant_walk.glb",
			"script": "res://scripts/giant.gd",
			"flavor": "A lumbering behemoth that ignores troops entirely and marches straight for your towers. Slow, but nearly unstoppable.",
			"stats": [["Role", "Tank"], ["Health", "180"], ["Damage", "30"], ["Targets", "Buildings"], ["Move speed", "Slow"]],
			"level_stats": ["Health", "Damage"],
		},
		{
			# Bomber: fast, fragile suicide unit — jumps and explodes for big AoE.
			"id": "bomber", "name": "Bomber", "unlock_cost": 80,
			"texture": "res://ui/skeleton_button.png", "cost": 2.0, "scale": 1.3,
			"glb": "res://models/skeleton/skeleton_walk.glb",
			"script": "res://scripts/bomber.gd",
			"flavor": "Sprints in and leaps into a fiery blast that engulfs everything nearby. One use — but what a boom.",
			"stats": [["Role", "Suicide"], ["Health", "26"], ["Damage", "50 (AoE)"], ["Blast radius", "6.75"], ["Move speed", "Fast"]],
			"level_stats": ["Health", "Damage"],
		},
		{
			"id": "builder", "name": "Builder", "unlock_cost": 180,
			"texture": "res://ui/builder_button.png", "cost": 3.0, "scale": 1.3,
			"glb": "res://models/dwarf/dwarf_walk.glb",
			"script": "res://scripts/builder.gd",
			"flavor": "Won't throw a punch. Plants elixir pumps to keep your war machine fed — protect him and your economy soars.",
			"stats": [["Role", "Support"], ["Health", "35"], ["Damage", "—"], ["Builds", "Elixir pumps"], ["Move speed", "Slow"]],
			"level_stats": ["Health"],
		},
		{
			# Arrows: a targeted SPELL (not a unit). Aimed anywhere on the field; rains
			# a volley dealing AoE damage to enemy troops + buildings in the circle.
			"id": "arrows", "name": "Arrows", "unlock_cost": 100,
			"texture": "res://ui/arrows_button.png", "cost": 3.0, "scale": 1.0,
			"kind": "spell", "radius": 4.0, "damage": 32.0,
			"flavor": "A volley that rains down anywhere on the field, peppering everything in a wide circle. Wipes out swarms and finishes the wounded.",
			"stats": [["Role", "Spell"], ["Damage", "32 (AoE)"], ["Radius", "4.0"], ["Aim", "Anywhere"]],
			"level_stats": ["Damage"],
		},
		{
			# Freeze: a targeted SPELL that locks every enemy unit + building in the circle
			# in a block of ice for a few seconds — they can't move, attack or animate.
			"id": "freeze", "name": "Freeze",
			"texture": "res://ui/freeze_button.png", "cost": 1.0, "scale": 1.0,
			"kind": "spell", "spell_type": "freeze", "radius": 3.5, "freeze_time": 4.5,
			"flavor": "Encases every enemy troop and building in the circle in solid ice. Stop a push cold, then punish the helpless.",
			"stats": [["Role", "Spell"], ["Effect", "Freeze"], ["Duration", "4.5s"], ["Radius", "3.5"], ["Aim", "Anywhere"]],
			"level_stats": ["Duration"],
		},
		{
			# Cannon: a placeable defensive building (kind "building"). Stands still,
			# fires at the nearest enemy in range, and slowly rots away. (id stays
			# "archer_tower" so saved unlocks/loadouts keep working.)
			"id": "archer_tower", "name": "Cannon", "unlock_cost": 150,
			"texture": "res://ui/cannon_button.png", "cost": 4.0, "scale": 2.6,
			"kind": "building",
			"range": 10.0,   # attack range — shown as a circle while placing (matches archer_tower.gd)
			"glb": "res://models/cannon/cannon.glb",
			"script": "res://scripts/archer_tower.gd",
			"flavor": "A stout iron cannon that pounds the nearest enemy in range. It slowly rusts away on its own, so it only stands for a while — make it count.",
			"stats": [["Role", "Building"], ["Health", "70"], ["Damage", "6 / shot"], ["Range", "10"], ["Decays", "3 hp/sec"]],
			"level_stats": ["Health", "Damage"],
		},
	]

static func by_id(id: String) -> Dictionary:
	for c in all():
		if c["id"] == id:
			return c
	return {}

# The 3 chosen card ids in slot order, validated to be known + distinct. Falls back
# to the default trio if the saved value is missing or malformed.
static func load_loadout(settings_path: String = SETTINGS_PATH) -> Array:
	var cfg := ConfigFile.new()
	cfg.load(settings_path)
	var raw = cfg.get_value("loadout", "cards", [])
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
