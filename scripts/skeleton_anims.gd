extends RefCounted
class_name SkeletonAnims
# The Bomb-Carrying Skeleton (bomber) ships ONE animation per GLB, all on the same
# Armature. Load the extra clips (run / dead / basic-jump) once and cache them; the
# walk clip comes from the base (Walking) GLB itself. The Basic_Jump clip is the
# wind-up for its suicide explosion. All clips share the skeleton, so tracks resolve
# against any unit's AnimationPlayer. Mirrors VikingAnims / DwarfAnims.

const SOURCES := [
	"res://models/skeleton/Meshy_AI_Bomb_Carrying_Skeleto_biped_Animation_Running_withSkin.glb",
	"res://models/skeleton/Meshy_AI_Bomb_Carrying_Skeleto_biped_Animation_Dead_withSkin.glb",
	"res://models/skeleton/Meshy_AI_Bomb_Carrying_Skeleto_biped_Animation_Basic_Jump_withSkin.glb",
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
