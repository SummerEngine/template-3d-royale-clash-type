# Sfx: fire-and-forget sound effects. Reference a clip by base path WITHOUT an
# extension; we resolve .ogg/.wav/.mp3 at load time (Godot caches the result),
# so it's null-safe if a clip isn't present/imported yet (just stays silent).
# Usage:  Sfx.play(self, "res://audio/sword_hit")
#         Sfx.play(self, "res://audio/barbarian_spawn", -6.0)   # quieter
extends RefCounted

const _EXTS: Array[String] = [".ogg", ".wav", ".mp3"]

static func _stream(base_path: String) -> AudioStream:
	for ext in _EXTS:
		var p := base_path + ext
		if ResourceLoader.exists(p):
			var r = load(p)
			if r is AudioStream:
				return r
	return null

# ctx: any node currently in the tree (used to reach the SceneTree).
static func play(ctx: Node, base_path: String, volume_db: float = 0.0, pitch_var: float = 0.06) -> void:
	if not is_instance_valid(ctx) or not ctx.is_inside_tree():
		return
	var stream := _stream(base_path)
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.volume_db = volume_db
	if AudioServer.get_bus_index(&"SFX") != -1:
		p.bus = &"SFX"   # routed through the SFX bus so the options slider controls it
	p.pitch_scale = 1.0 + randf_range(-pitch_var, pitch_var)
	# Parent to the tree root so the sound finishes even if ctx frees (deaths).
	ctx.get_tree().root.add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
