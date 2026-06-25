class_name Profile
extends RefCounted
## Persistent player progression — level + XP — saved to user://settings.cfg under
## the [profile] section (same file as [audio] and [loadout]). user:// is a real
## OS save directory, so this survives closing and reopening the app.

const SETTINGS_PATH := "user://settings.cfg"
const WIN_XP := 100   # XP for a win
const LOSS_XP := 30   # consolation XP for a loss
const WIN_COINS := 50   # coins for a win
const LOSS_COINS := 15  # consolation coins for a loss

# XP required to advance FROM `level` to the next. Escalates each level so later
# levels take longer (100, 150, 200, ...).
static func xp_to_next(level: int) -> int:
	return 100 + (level - 1) * 50

static func get_level() -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return int(cfg.get_value("profile", "level", 1))

static func get_xp() -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return int(cfg.get_value("profile", "xp", 0))

static func get_coins() -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	return int(cfg.get_value("profile", "coins", 0))

# Add (or spend, with a negative amount) coins; persists and returns the new total.
static func add_coins(amount: int) -> int:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)
	var total := int(cfg.get_value("profile", "coins", 0)) + amount
	cfg.set_value("profile", "coins", total)
	cfg.save(SETTINGS_PATH)
	return total

# Award XP, roll over any completed levels, persist, and return a summary the UI
# can display: { gained, old_level, level, leveled_up, xp, to_next }.
static func add_xp(amount: int) -> Dictionary:
	var cfg := ConfigFile.new()
	cfg.load(SETTINGS_PATH)   # keep [audio]/[loadout] intact
	var level := int(cfg.get_value("profile", "level", 1))
	var xp := int(cfg.get_value("profile", "xp", 0))
	var old_level := level
	var start_xp := xp          # xp within the starting level, before the gain
	xp += amount
	while xp >= xp_to_next(level):
		xp -= xp_to_next(level)
		level += 1
	cfg.set_value("profile", "level", level)
	cfg.set_value("profile", "xp", xp)
	cfg.save(SETTINGS_PATH)
	return {
		"gained": amount,
		"start_level": old_level,   # for animating the fill from where it began
		"start_xp": start_xp,
		"old_level": old_level,
		"level": level,
		"leveled_up": level > old_level,
		"xp": xp,
		"to_next": xp_to_next(level),
	}
