class_name TownCloudStorage
extends RefCounted
## Stores town state in Steam Cloud as JSON.
## Handles town name, gateway links, entities, and modifications.

signal load_completed(success: bool)
signal save_completed(success: bool)

const CLOUD_FILE_NAME: String = "town_state.json"
const SAVE_VERSION: int = 1

var _state: Dictionary = {}
var _save_timer: Timer = null
var _save_pending: bool = false
var _is_new_town: bool = false


func _init() -> void:
	_initialize_empty()


func setup(parent: Node) -> void:
	_setup_save_timer(parent)


func _initialize_empty() -> void:
	_state = {
		"version": SAVE_VERSION,
		"town_name": "",
		"last_saved": "",
		"gateways": [],
		"entities": [],
		"modifications": []
	}
	# Initialize 4 empty gateway slots
	var gateways: Array = _state["gateways"]
	for i: int in range(4):
		gateways.append({
			"id": i,
			"linked_lobby_id": 0,
			"linked_map_name": "",
			"generation_seed": 0,
			"pearl_type": ""
		})


func _setup_save_timer(parent: Node) -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 1.0  # Slightly longer debounce for town state
	@warning_ignore("return_value_discarded")
	_save_timer.timeout.connect(_on_save_timer_timeout)
	parent.add_child(_save_timer)


func _on_save_timer_timeout() -> void:
	_save_immediately()


func _save_immediately() -> void:
	_save_pending = false
	_do_save()


func _queue_save() -> void:
	_save_pending = true
	if _save_timer != null:
		_save_timer.start()


func flush() -> void:
	if _save_pending:
		_save_immediately()


# =============================================================================
# Public API
# =============================================================================

## Check if this is a newly created town (no existing save)
func is_new_town() -> bool:
	return _is_new_town


## Get the town name
func get_town_name() -> String:
	return _state.get("town_name", "")


## Set the town name and queue save
func set_town_name(name: String) -> void:
	_state["town_name"] = name
	_queue_save()


## Get gateway data by ID
func get_gateway(gateway_id: int) -> Dictionary:
	var gateways_variant: Variant = _state.get("gateways", [])
	if gateways_variant is Array:
		@warning_ignore("unsafe_cast")
		var gateways: Array = gateways_variant as Array
		if gateway_id >= 0 and gateway_id < gateways.size():
			var gateway: Variant = gateways[gateway_id]
			if gateway is Dictionary:
				@warning_ignore("unsafe_cast", "unsafe_method_access")
				return (gateway as Dictionary).duplicate()
	return {"id": gateway_id, "linked_lobby_id": 0, "linked_map_name": "", "generation_seed": 0, "pearl_type": ""}


## Set gateway configuration (seed, name, and pearl type, no lobby yet)
func set_gateway_config(gateway_id: int, field_seed: int, map_name: String, pearl_type: StringName = &"") -> void:
	var gateways_variant: Variant = _state.get("gateways", [])
	if not gateways_variant is Array:
		return
	@warning_ignore("unsafe_cast")
	var gateways: Array = gateways_variant as Array
	if gateway_id >= 0 and gateway_id < gateways.size():
		gateways[gateway_id] = {
			"id": gateway_id,
			"linked_lobby_id": 0,
			"linked_map_name": map_name,
			"generation_seed": field_seed,
			"pearl_type": String(pearl_type)
		}
		_queue_save()


## Set gateway link and queue save
func set_gateway_link(gateway_id: int, lobby_id: int, map_name: String) -> void:
	var gateways_variant: Variant = _state.get("gateways", [])
	if not gateways_variant is Array:
		return
	@warning_ignore("unsafe_cast")
	var gateways: Array = gateways_variant as Array
	if gateway_id >= 0 and gateway_id < gateways.size():
		# Preserve existing seed and pearl_type if any
		var existing: Variant = gateways[gateway_id]
		var existing_seed: int = 0
		var existing_pearl_type: String = ""
		if existing is Dictionary:
			@warning_ignore("unsafe_cast")
			var existing_dict: Dictionary = existing as Dictionary
			existing_seed = existing_dict.get("generation_seed", 0)
			existing_pearl_type = existing_dict.get("pearl_type", "")
		gateways[gateway_id] = {
			"id": gateway_id,
			"linked_lobby_id": lobby_id,
			"linked_map_name": map_name,
			"generation_seed": existing_seed,
			"pearl_type": existing_pearl_type
		}
		_queue_save()


## Clear gateway link
func clear_gateway_link(gateway_id: int) -> void:
	var gateways_variant: Variant = _state.get("gateways", [])
	if not gateways_variant is Array:
		return
	@warning_ignore("unsafe_cast")
	var gateways: Array = gateways_variant as Array
	if gateway_id >= 0 and gateway_id < gateways.size():
		gateways[gateway_id] = {
			"id": gateway_id,
			"linked_lobby_id": 0,
			"linked_map_name": "",
			"generation_seed": 0,
			"pearl_type": ""
		}
		_queue_save()


## Get all entities
func get_entities() -> Array:
	var entities_variant: Variant = _state.get("entities", [])
	if entities_variant is Array:
		@warning_ignore("unsafe_cast")
		return (entities_variant as Array).duplicate()
	return []


## Set all entities and queue save
func set_entities(entities: Array) -> void:
	_state["entities"] = entities.duplicate()
	_queue_save()


## Add an entity
func add_entity(entity: Dictionary) -> void:
	var entities_variant: Variant = _state.get("entities", [])
	if not entities_variant is Array:
		return
	@warning_ignore("unsafe_cast")
	var entities: Array = entities_variant as Array
	entities.append(entity.duplicate())
	_queue_save()


## Remove entity by matching criteria
func remove_entity(match_criteria: Dictionary) -> bool:
	var entities: Array = _state.get("entities", [])
	for i: int in range(entities.size() - 1, -1, -1):
		var entity: Dictionary = entities[i]
		var matches: bool = true
		for key: String in match_criteria:
			if entity.get(key) != match_criteria[key]:
				matches = false
				break
		if matches:
			entities.remove_at(i)
			_queue_save()
			return true
	return false


# =============================================================================
# Load Implementation
# =============================================================================

func load_state() -> void:
	_is_new_town = false

	if not SteamManager.is_steam_initialized:
		_initialize_empty()
		_is_new_town = true
		load_completed.emit(true)
		return

	var steam: Object = SteamManager.get_steam()
	if steam == null:
		_initialize_empty()
		_is_new_town = true
		load_completed.emit(true)
		return

	@warning_ignore("unsafe_method_access")
	var file_exists: bool = steam.fileExists(CLOUD_FILE_NAME)

	if not file_exists:
		_initialize_empty()
		_is_new_town = true
		load_completed.emit(true)
		return

	@warning_ignore("unsafe_method_access")
	var file_size: int = steam.getFileSize(CLOUD_FILE_NAME)

	if file_size <= 0:
		_initialize_empty()
		_is_new_town = true
		load_completed.emit(true)
		return

	@warning_ignore("unsafe_method_access")
	var file_data: Variant = steam.fileRead(CLOUD_FILE_NAME, file_size)

	var buffer: PackedByteArray = _extract_file_buffer(file_data)

	if buffer.is_empty():
		_initialize_empty()
		_is_new_town = true
		load_completed.emit(true)
		return

	var json_string: String = buffer.get_string_from_utf8()

	if json_string.strip_edges().is_empty():
		_initialize_empty()
		_is_new_town = true
		load_completed.emit(true)
		return

	var parsed: Variant = JSON.parse_string(json_string)

	if parsed is Dictionary:
		@warning_ignore("unsafe_cast")
		_load_from_dict(parsed as Dictionary)
		load_completed.emit(true)
	else:
		push_warning("TownCloudStorage: Failed to parse town state")
		_initialize_empty()
		_is_new_town = true
		load_completed.emit(false)


func _load_from_dict(data: Dictionary) -> void:
	var version: int = data.get("version", 1)

	var entities_data: Variant = data.get("entities", [])
	var mods_data: Variant = data.get("modifications", [])
	var entities_array: Array = []
	var mods_array: Array = []
	if entities_data is Array:
		@warning_ignore("unsafe_cast")
		entities_array = (entities_data as Array).duplicate()
	if mods_data is Array:
		@warning_ignore("unsafe_cast")
		mods_array = (mods_data as Array).duplicate()
	_state = {
		"version": SAVE_VERSION,
		"town_name": data.get("town_name", ""),
		"last_saved": data.get("last_saved", ""),
		"gateways": [],
		"entities": entities_array,
		"modifications": mods_array
	}

	# Load gateways with defaults for missing slots
	var loaded_gateways_variant: Variant = data.get("gateways", [])
	var loaded_gateways: Array = []
	if loaded_gateways_variant is Array:
		@warning_ignore("unsafe_cast")
		loaded_gateways = loaded_gateways_variant as Array
	var state_gateways: Array = _state["gateways"]
	for i: int in range(4):
		if i < loaded_gateways.size():
			var gateway: Variant = loaded_gateways[i]
			if gateway is Dictionary:
				@warning_ignore("unsafe_cast", "unsafe_method_access")
				var gw_dict: Dictionary = (gateway as Dictionary).duplicate()
				# Ensure pearl_type field exists for older saves
				if not gw_dict.has("pearl_type"):
					gw_dict["pearl_type"] = ""
				state_gateways.append(gw_dict)
			else:
				state_gateways.append({
					"id": i, "linked_lobby_id": 0, "linked_map_name": "", "generation_seed": 0, "pearl_type": ""
				})
		else:
			state_gateways.append({
				"id": i, "linked_lobby_id": 0, "linked_map_name": "", "generation_seed": 0, "pearl_type": ""
			})

	# If version changed, queue a save
	if version < SAVE_VERSION:
		_queue_save()


# =============================================================================
# Save Implementation
# =============================================================================

func _do_save() -> void:
	if not SteamManager.is_steam_initialized:
		push_warning("TownCloudStorage: Steam not initialized, cannot save")
		save_completed.emit(false)
		return

	var steam: Object = SteamManager.get_steam()
	if steam == null:
		push_warning("TownCloudStorage: Steam singleton not available")
		save_completed.emit(false)
		return

	@warning_ignore("unsafe_method_access")
	var cloud_enabled_account: bool = steam.isCloudEnabledForAccount()
	@warning_ignore("unsafe_method_access")
	var cloud_enabled_app: bool = steam.isCloudEnabledForApp()

	if not cloud_enabled_account:
		push_warning("TownCloudStorage: Steam Cloud disabled in user's Steam settings")
		save_completed.emit(false)
		return
	if not cloud_enabled_app:
		push_warning("TownCloudStorage: Steam Cloud not configured for this app")
		save_completed.emit(false)
		return

	@warning_ignore("unsafe_method_access")
	var quota: Dictionary = steam.getQuota()
	var available_bytes: int = quota.get("available_bytes", 0)

	# Update timestamp
	_state["last_saved"] = Time.get_datetime_string_from_system(true)
	_state["version"] = SAVE_VERSION

	var json_string: String = JSON.stringify(_state)
	var data_size: int = json_string.to_utf8_buffer().size()

	if data_size > available_bytes:
		push_warning("TownCloudStorage: Not enough Cloud storage (need %d, have %d)" % [
			data_size, available_bytes
		])
		save_completed.emit(false)
		return

	var write_buffer: PackedByteArray = json_string.to_utf8_buffer()

	@warning_ignore("unsafe_method_access")
	var success: bool = steam.fileWrite(CLOUD_FILE_NAME, write_buffer)

	if success:
		_is_new_town = false
		print("TownCloudStorage: Saved town state")
		save_completed.emit(true)
	else:
		push_warning("TownCloudStorage: fileWrite failed")
		save_completed.emit(false)


# =============================================================================
# Helpers
# =============================================================================

static func _extract_file_buffer(file_data: Variant) -> PackedByteArray:
	if file_data is PackedByteArray:
		@warning_ignore("unsafe_cast")
		return file_data as PackedByteArray
	if file_data is Dictionary:
		@warning_ignore("unsafe_cast")
		var file_dict: Dictionary = file_data as Dictionary
		var buf_variant: Variant = file_dict.get("buf", null)
		if buf_variant is PackedByteArray:
			@warning_ignore("unsafe_cast")
			return buf_variant as PackedByteArray
		if buf_variant is Array:
			@warning_ignore("unsafe_cast")
			var arr: Array = buf_variant as Array
			var result: PackedByteArray = PackedByteArray()
			@warning_ignore("return_value_discarded")
			result.resize(arr.size())
			for i: int in range(arr.size()):
				var byte_val: Variant = arr[i]
				if byte_val is int:
					@warning_ignore("unsafe_cast")
					result[i] = byte_val as int
				elif byte_val is float:
					@warning_ignore("unsafe_cast")
					result[i] = int(byte_val as float)
			return result
	return PackedByteArray()
