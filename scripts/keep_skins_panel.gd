extends CanvasLayer

var _box: VBoxContainer
var _service

func _ready() -> void:
	add_to_group("keep_skins_modal")
	layer = 30
	_service = get_node("/root/KeepSkins")
	var shade := ColorRect.new()
	shade.color = Color(0.03, 0.04, 0.08, 0.96)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 30)
	shade.add_child(margin)
	var scroll := ScrollContainer.new()
	margin.add_child(scroll)
	_box = VBoxContainer.new()
	_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_box.add_theme_constant_override("separation", 18)
	scroll.add_child(_box)
	_service.changed.connect(_render)
	_render()
	_service.refresh()

func _render() -> void:
	for child in _box.get_children():
		_box.remove_child(child)
		child.queue_free()
	var title := Label.new()
	title.text = "Keep Skins"
	title.add_theme_font_size_override("font_size", 34)
	_box.add_child(title)
	var info := Label.new()
	info.text = _service.message
	info.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_box.add_child(info)
	for style in ["default", "gilded", "emerald"]:
		var row := Button.new()
		row.custom_minimum_size.y = 80
		var display_name: String = {"default": "Default", "gilded": "Rose Gold Keep", "emerald": "Emerald Keep"}[style]
		var owned: bool = style == "default" or style in _service.state.owned
		if style == _service.state.selected:
			row.text = display_name + " · Equipped"
			row.disabled = true
		elif owned:
			row.text = display_name + " · Equip"
			row.pressed.connect(_service.equip.bind(style))
		elif _service.offers.has(style):
			row.text = display_name + " · %d Sparks · Buy in Summer" % _service.offers[style].get_sparks_amount()
			row.disabled = _service.busy()
			row.pressed.connect(_service.buy.bind(style))
		else:
			row.text = display_name + " · Unavailable"
			row.disabled = true
		_box.add_child(row)
	var refresh := Button.new()
	refresh.text = "Refresh inventory"
	refresh.custom_minimum_size.y = 60
	refresh.pressed.connect(_service.refresh)
	_box.add_child(refresh)
	var close := Button.new()
	close.text = "Back"
	close.custom_minimum_size.y = 60
	close.pressed.connect(queue_free)
	_box.add_child(close)

func _exit_tree() -> void:
	if _service != null:
		_service.changed.disconnect(_render)
