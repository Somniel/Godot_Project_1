class_name SteamCloudStorage
extends InventoryStorage
## Stores inventory in Steam Cloud as JSON.
## Handles save versioning and item ID migrations for backwards compatibility.

const CLOUD_FILE_NAME: String = "inventory.json"
const SAVE_VERSION: int = 2

## Item ID migrations from old versions (old_id -> new_id)
const ITEM_ID_MIGRATIONS: Dictionary = {
	&"pearl": &"air_pearl",  # v1 -> v2: renamed pearl to air_pearl
}

var _slots: Array[Dictionary] = []
var _save_timer: Timer = null
var _save_pending: bool = false


func _init() -> void:
	_initialize_empty()


func setup(parent: Node) -> void:
	_setup_save_timer(parent)


func _initialize_empty() -> void:
	_slots.clear()
	for i: int in range(INVENTORY_SIZE):
		_slots.append({})


func _setup_save_timer(parent: Node) -> void:
	_save_timer = Timer.new()
	_save_timer.one_shot = true
	_save_timer.wait_time = 0.5
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
	_save_timer.start()


func flush() -> void:
	if _save_pending:
		_save_immediately()


# =============================================================================
# InventoryStorage Interface
# =============================================================================

func load_inventory() -> void:
	if not SteamManager.is_steam_initialized:
		_initialize_empty()
		load_completed.emit(true)
		return

	var steam: Object = SteamManager.get_steam()
	if steam == null:
		_initialize_empty()
		load_completed.emit(true)
		return

	@warning_ignore("unsafe_method_access")
	var file_exists: bool = steam.fileExists(CLOUD_FILE_NAME)

	if not file_exists:
		_initialize_empty()
		load_completed.emit(true)
		return

	@warning_ignore("unsafe_method_access")
	var file_size: int = steam.getFileSize(CLOUD_FILE_NAME)

	if file_size <= 0:
		_initialize_empty()
		load_completed.emit(true)
		return

	@warning_ignore("unsafe_method_access")
	var file_data: Variant = steam.fileRead(CLOUD_FILE_NAME, file_size)

	var buffer: PackedByteArray = _extract_file_buffer(file_data)

	if buffer.is_empty():
		_initialize_empty()
		load_completed.emit(true)
		return

	var json_string: String = buffer.get_string_from_utf8()

	# Check for empty or whitespace-only string before parsing
	if json_string.strip_edges().is_empty():
		_initialize_empty()
		load_completed.emit(true)
		return

	var parsed: Variant = JSON.parse_string(json_string)

	if parsed is Dictionary:
		@warning_ignore("unsafe_cast")
		_load_from_dict(parsed as Dictionary)
		load_completed.emit(true)
	else:
		push_warning("SteamCloudStorage: Failed to parse inventory data")
		_initialize_empty()
		load_completed.emit(false)


func save_inventory(slots: Array[Dictionary]) -> void:
	_slots.clear()
	for slot: Dictionary in slots:
		_slots.append(slot.duplicate())
	_queue_save()


func get_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: Dictionary in _slots:
		result.append(slot.duplicate())
	return result


# =============================================================================
# Save Implementation
# =============================================================================

func _do_save() -> void:
	if not SteamManager.is_steam_initialized:
		push_warning("SteamCloudStorage: Steam not initialized, cannot save")
		save_completed.emit(false)
		return

	var steam: Object = SteamManager.get_steam()
	if steam == null:
		push_warning("SteamCloudStorage: Steam singleton not available")
		save_completed.emit(false)
		return

	# Check if Steam Cloud is enabled
	@warning_ignore("unsafe_method_access")
	var cloud_enabled_account: bool = steam.isCloudEnabledForAccount()
	@warning_ignore("unsafe_method_access")
	var cloud_enabled_app: bool = steam.isCloudEnabledForApp()

	if not cloud_enabled_account:
		push_warning("SteamCloudStorage: Steam Cloud disabled in user's Steam settings")
		save_completed.emit(false)
		return
	if not cloud_enabled_app:
		push_warning("SteamCloudStorage: Steam Cloud not configured for this app in Steamworks")
		save_completed.emit(false)
		return

	# Check quota
	@warning_ignore("unsafe_method_access")
	var quota: Dictionary = steam.getQuota()
	var total_bytes: int = quota.get("total_bytes", 0)
	var available_bytes: int = quota.get("available_bytes", 0)

	if total_bytes == 0:
		push_warning("SteamCloudStorage: Steam Cloud quota is 0 - configure Cloud in Steamworks")
		save_completed.emit(false)
		return

	var slots_array: Array = []
	for slot: Dictionary in _slots:
		if slot.is_empty():
			slots_array.append(null)
		else:
			slots_array.append({
				"item_id": str(_get_slot_item_id(slot)),
				"quantity": _get_slot_quantity(slot)
			})

	var save_data: Dictionary = {
		"version": SAVE_VERSION,
		"slots": slots_array
	}

	var json_string: String = JSON.stringify(save_data)
	var data_size: int = json_string.to_utf8_buffer().size()

	if data_size > available_bytes:
		push_warning("SteamCloudStorage: Not enough Cloud storage (need %d, have %d)" % [
			data_size, available_bytes
		])
		save_completed.emit(false)
		return

	var write_buffer: PackedByteArray = json_string.to_utf8_buffer()

	@warning_ignore("unsafe_method_access")
	var success: bool = steam.fileWrite(CLOUD_FILE_NAME, write_buffer)

	if success:
		save_completed.emit(true)
	else:
		push_warning("SteamCloudStorage: fileWrite failed - check Steamworks Cloud configuration")
		save_completed.emit(false)


# =============================================================================
# Load Helpers
# =============================================================================

func _load_from_dict(data: Dictionary) -> void:
	var version: int = data.get("version", 1)
	var slots_data: Array = data.get("slots", [])

	_initialize_empty()

	for i: int in range(mini(slots_data.size(), INVENTORY_SIZE)):
		var slot_data: Variant = slots_data[i]
		if slot_data is Dictionary:
			@warning_ignore("unsafe_cast")
			var slot_dict: Dictionary = slot_data as Dictionary
			if slot_dict.has("item_id"):
				var item_id: StringName = _get_slot_item_id(slot_dict)
				var quantity: int = _get_slot_quantity(slot_dict)

				# Apply migrations for older save versions
				if version < SAVE_VERSION:
					item_id = _migrate_item_id(item_id)

				if item_id != &"" and quantity > 0:
					_slots[i] = {"item_id": item_id, "quantity": quantity}

	# If migrated, queue a save with the new version
	if version < SAVE_VERSION:
		_queue_save()


func _migrate_item_id(item_id: StringName) -> StringName:
	## Converts old item IDs to current IDs using the migration table.
	if ITEM_ID_MIGRATIONS.has(item_id):
		var new_id: StringName = ITEM_ID_MIGRATIONS[item_id]
		return new_id
	return item_id


# =============================================================================
# Dictionary Helper Functions
# =============================================================================

static func _get_slot_item_id(slot: Dictionary) -> StringName:
	## Safely extract item_id from slot dictionary.
	var value: Variant = slot.get("item_id", "")
	if value is StringName:
		@warning_ignore("unsafe_cast")
		return value as StringName
	if value is String:
		@warning_ignore("unsafe_cast")
		return StringName(value as String)
	return &""


static func _get_slot_quantity(slot: Dictionary) -> int:
	## Safely extract quantity from slot dictionary.
	var value: Variant = slot.get("quantity", 0)
	if value is int:
		@warning_ignore("unsafe_cast")
		return value as int
	if value is float:
		@warning_ignore("unsafe_cast")
		return int(value as float)
	return 0


static func _extract_file_buffer(file_data: Variant) -> PackedByteArray:
	## Extracts the byte buffer from Steam fileRead result.
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
