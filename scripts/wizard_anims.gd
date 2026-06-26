extends RefCounted
class_name WizardAnims
# The Violet Archmage wizard ships ONE animation per GLB, all on the same Armature.
# Load the extra clips (cast / idle / run / dead) once and cache them; the walk clip
# comes from the running GLB itself. All clips share the same skeleton, so the
# tracks resolve against any unit's AnimationPlayer.

const SOURCES := [
	"res://models/wizard/wizard_cast.glb",
	"res://models/wizard/wizard_idle02.glb",
	"res://models/wizard/wizard_run.glb",
	"res://models/wizard/wizard_dead.glb",
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
