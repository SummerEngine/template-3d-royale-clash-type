extends Node
## Authenticated SDK adapter. No HTTP, prices, credentials, or purchase grants.
signal changed
const POLICY := preload("res://scripts/keep_skin_state.gd")
var state = POLICY.new()
var message := "Skins are unavailable until the published catalog is configured."
var offers := {}
var _catalog: Dictionary = {}
var _runtime
var _client
var _inventory
var _store
var _binding := ""
var _generation := 0
var _refreshing := false
var _inventory_verified := false

func _ready() -> void:
	_catalog = JSON.parse_string(FileAccess.get_file_as_string("res://scripts/keep_skin_catalog.json"))
	if not Engine.has_singleton("Summer") or str(_catalog.get("game_id", "")).is_empty():
		return
	_runtime = Engine.get_singleton("Summer")
	var result = await _runtime.initialize(str(_catalog.game_id)).get_result_or_completed_signal()
	if not result.is_ok():
		message = result.get_message()
		changed.emit()
		return
	_sync_binding()

func _process(_delta: float) -> void:
	# Reads local immutable context only; never polls inventory or the network.
	if _runtime != null:
		_sync_binding()

func _sync_binding() -> void:
	var client = _runtime.get_client() if _runtime.get_state() == _runtime.STATE_READY else null
	var user := ""
	if client != null and client.get_context() != null and client.get_context().get_game().get_game_id() == str(_catalog.game_id):
		var player = client.get_context().get_player()
		if player != null and not player.is_guest() and not player.is_local():
			user = player.get_user_id()
	var binding := user + ":" + str(client.get_instance_id() if client != null else 0)
	if binding == _binding:
		return
	_disconnect()
	_binding = binding
	_generation += 1
	offers.clear()
	_refreshing = false
	_inventory_verified = false
	var game := str(_catalog.get("game_id", ""))
	state.bind(user, game, "default")
	if user.is_empty():
		message = "Sign in to Summer to use owned skins."
		changed.emit()
		return
	_client = client
	_inventory = client.get_items()
	_store = client.get_store()
	_inventory.refreshed.connect(_inventory_changed)
	_inventory.item_replaced.connect(_inventory_changed)
	_inventory.item_removed.connect(_inventory_changed)
	_store.checkout_status_changed.connect(_checkout_changed)
	changed.emit()
	refresh()

func _disconnect() -> void:
	if _inventory != null:
		_inventory.refreshed.disconnect(_inventory_changed)
		_inventory.item_replaced.disconnect(_inventory_changed)
		_inventory.item_removed.disconnect(_inventory_changed)
	if _store != null:
		_store.checkout_status_changed.disconnect(_checkout_changed)
	_inventory = null
	_store = null
	_client = null

func _exit_tree() -> void:
	_disconnect()

func refresh() -> void:
	if _inventory == null or _refreshing:
		return
	_refreshing = true
	var generation := _generation
	message = "Loading owned skins…"
	changed.emit()
	var result = await _inventory.refresh().get_result_or_completed_signal()
	_sync_binding()
	if generation != _generation:
		return
	if not result.is_ok():
		_refreshing = false
		_inventory_verified = false
		state.reconcile([], false, _catalog.definitions)
		message = result.get_message()
		changed.emit()
		return
	_inventory_verified = true
	state.load_preference()
	_inventory_changed()
	await _browse(generation)
	if generation == _generation:
		_refreshing = false

func _browse(generation: int) -> void:
	offers.clear()
	var cursor := ""
	var seen := {}
	while true:
		var operation = _store.list_items(50, cursor)
		var result = await operation.get_result_or_completed_signal()
		_sync_binding()
		if generation != _generation:
			return
		if not result.is_ok():
			message = result.get_message()
			break
		for item in operation.get_items():
			if item.get_game_id() != str(_catalog.game_id):
				continue
			for style in ["gilded", "emerald"]:
				if item.get_item_id() == str(_catalog.store_items.get(style, "")) and item.get_price() != null:
					offers[style] = item.get_price()
		cursor = operation.get_next_cursor()
		if cursor.is_empty() or seen.has(cursor):
			break
		seen[cursor] = true
	changed.emit()

func _inventory_changed(_change = null) -> void:
	if _inventory == null:
		return
	var definitions: Array[String] = []
	for item in _inventory.get_owned_items():
		definitions.append(item.get_definition_id())
	state.reconcile(definitions, _inventory_verified and _inventory.is_projection_loaded(), _catalog.definitions)
	message = "Choose a keep appearance. Purchases open Summer’s confirmation."
	_render_checkout()

func equip(style: String) -> void:
	if _runtime != null:
		_sync_binding()
		_inventory_changed()
	if not state.equip(style):
		return
	if not state.account.is_empty():
		if state.save_preference() != OK:
			message = "Equipped for this session; Summer could not save the preference."
	changed.emit()

func busy() -> bool:
	return _store != null and _store.has_pending_checkouts()

func buy(style: String) -> void:
	if _runtime != null:
		_sync_binding()
	if _store == null or busy() or not offers.has(style):
		return
	var generation := _generation
	var lines: Array[SummerCheckoutLine] = [SummerCheckoutLine.create(offers[style].get_offer_id())]
	var operation = _store.request_checkout(lines)
	changed.emit()
	await operation.get_result_or_completed_signal()
	_sync_binding()
	if generation != _generation:
		return
	_render_checkout(operation)

func _checkout_changed(_status) -> void:
	_render_checkout()

func _render_checkout(operation = null) -> void:
	var view = SummerCheckoutObservation.capture(_store, operation)
	var rows: Array[String] = []
	for status in view.get_statuses():
		var label := str(status.get_state())
		if status.get_error_code() == &"insufficient_funds":
			label = "Not enough Sparks."
		elif label == "purchased":
			label = "Purchased — ownership updates from Summer inventory."
		elif label == "declined":
			label = "Cancelled"
		rows.append(label)
	if rows.is_empty() and view.has_pending_checkouts():
		rows.append("Waiting for Summer checkout…")
	if view.get_submission_failure() != null:
		rows.append(view.get_submission_failure().get_message())
	if not rows.is_empty():
		message = "\n".join(rows)
	# A receipt is presentation only: never equips or inserts an owned item.
	changed.emit()
