extends RefCounted
class_name DwarfAnims
# The Flying Dwarf builder ships ONE animation per GLB, all on the same Armature
# (same 24-bone skeleton as the viking). Load the extra clips (idle / run / dead /
# hammer-swing / attack) once and cache them; the walk clip comes from the running
# GLB itself. All clips share the skeleton, so tracks resolve against any unit's
# AnimationPlayer. Mirrors WizardAnims / VikingAnims.

const SOURCES := [
	"res://models/dwarf/dwarf_idle02.glb",
	"res://models/dwarf/dwarf_run.glb",
	"res://models/dwarf/dwarf_dead.glb",
	"res://models/dwarf/dwarf_hammer.glb",
	"res://models/dwarf/dwarf_attack.glb",
]

static var _clips: Dictionary = {}   # animation name -> Animation
static var _built: bool = false

# Built once and cached. Returns { clip_name: Animation }.
static func clips() -> Dictionary:
	if _built:
		return _clips
	_built = true
	for path in SOURCES:
		var ps = load(path)
		if ps == null:
			continue
		var inst = ps.instantiate()
		var ap := _find_ap(inst)
		if ap:
			var lib := ap.get_animation_library("")
			for n in lib.get_animation_list():
				_clips[n] = lib.get_animation(n).duplicate()
		inst.free()
	return _clips

static func _find_ap(n: Node) -> AnimationPlayer:
	for c in n.get_children():
		if c is AnimationPlayer:
			return c
		var f := _find_ap(c)
		if f:
			return f
	return null
