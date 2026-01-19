extends GutTest
## Unit tests for SteamCloudStorage.
## Tests serialization, deserialization, migration, and helper functions.
## Steam-dependent methods are tested for offline behavior only.


var _storage: SteamCloudStorage = null
var _timer_parent: Node = null


func before_each() -> void:
	_storage = SteamCloudStorage.new()
	# Create a parent node for the save timer
	_timer_parent = Node.new()
	add_child_autofree(_timer_parent)
	_storage.setup(_timer_parent)


func after_each() -> void:
	_storage = null
	_timer_parent = null


# =============================================================================
# Initialization Tests
# =============================================================================

func test_initial_slots_are_empty() -> void:
	var slots: Array[Dictionary] = _storage.get_slots()
	assert_eq(slots.size(), InventoryStorage.INVENTORY_SIZE, "Should have correct number of slots")
	for slot: Dictionary in slots:
		assert_true(slot.is_empty(), "All slots should be empty initially")


func test_inventory_size_constant() -> void:
	assert_eq(InventoryStorage.INVENTORY_SIZE, 25, "Inventory size should be 25")


# =============================================================================
# get_slots Tests
# =============================================================================

func test_get_slots_returns_copy() -> void:
	# Set up some data
	_storage._slots[0] = {"item_id": &"test_item", "quantity": 5}

	var slots: Array[Dictionary] = _storage.get_slots()
	slots[0]["quantity"] = 999  # Modify the copy

	# Original should be unchanged
	assert_eq(_storage._slots[0].get("quantity"), 5, "Should return copy, not reference")


func test_get_slots_returns_slot_copies() -> void:
	_storage._slots[0] = {"item_id": &"test_item", "quantity": 5}

	var slots: Array[Dictionary] = _storage.get_slots()
	var slot: Dictionary = slots[0]
	slot["quantity"] = 999

	# Original should be unchanged (deep copy)
	assert_eq(_storage._slots[0].get("quantity"), 5, "Should deep copy slot dictionaries")


# =============================================================================
# save_inventory Tests
# =============================================================================

func test_save_inventory_stores_slots() -> void:
	var test_slots: Array[Dictionary] = []
	for i: int in range(InventoryStorage.INVENTORY_SIZE):
		test_slots.append({})
	test_slots[0] = {"item_id": &"test_item", "quantity": 10}
	test_slots[5] = {"item_id": &"another_item", "quantity": 3}

	_storage.save_inventory(test_slots)

	var stored: Array[Dictionary] = _storage.get_slots()
	assert_eq(stored[0].get("item_id"), &"test_item", "Slot 0 should have test_item")
	assert_eq(stored[0].get("quantity"), 10, "Slot 0 should have quantity 10")
	assert_eq(stored[5].get("item_id"), &"another_item", "Slot 5 should have another_item")
	assert_true(stored[1].is_empty(), "Slot 1 should be empty")


func test_save_inventory_makes_copy() -> void:
	var test_slots: Array[Dictionary] = []
	for i: int in range(InventoryStorage.INVENTORY_SIZE):
		test_slots.append({})
	test_slots[0] = {"item_id": &"test_item", "quantity": 10}

	_storage.save_inventory(test_slots)

	# Modify original
	test_slots[0]["quantity"] = 999

	# Storage should have original value
	var stored: Array[Dictionary] = _storage.get_slots()
	assert_eq(stored[0].get("quantity"), 10, "Should store copy, not reference")


# =============================================================================
# _load_from_dict Tests
# =============================================================================

func test_load_from_dict_parses_valid_data() -> void:
	var data: Dictionary = {
		"version": 2,
		"slots": [
			{"item_id": "air_pearl", "quantity": 5},
			null,
			{"item_id": "flame_pearl", "quantity": 3}
		]
	}

	_storage._load_from_dict(data)

	var slots: Array[Dictionary] = _storage.get_slots()
	assert_eq(slots[0].get("item_id"), &"air_pearl", "Slot 0 should have air_pearl")
	assert_eq(slots[0].get("quantity"), 5, "Slot 0 should have quantity 5")
	assert_true(slots[1].is_empty(), "Slot 1 should be empty (was null)")
	assert_eq(slots[2].get("item_id"), &"flame_pearl", "Slot 2 should have flame_pearl")
	assert_eq(slots[2].get("quantity"), 3, "Slot 2 should have quantity 3")


func test_load_from_dict_handles_null_slots() -> void:
	var data: Dictionary = {
		"version": 2,
		"slots": [null, null, {"item_id": "test", "quantity": 1}, null]
	}

	_storage._load_from_dict(data)

	var slots: Array[Dictionary] = _storage.get_slots()
	assert_true(slots[0].is_empty(), "Null slot should become empty dict")
	assert_true(slots[1].is_empty(), "Null slot should become empty dict")
	assert_false(slots[2].is_empty(), "Valid slot should have data")
	assert_true(slots[3].is_empty(), "Null slot should become empty dict")


func test_load_from_dict_handles_empty_slots_array() -> void:
	var data: Dictionary = {
		"version": 2,
		"slots": []
	}

	_storage._load_from_dict(data)

	var slots: Array[Dictionary] = _storage.get_slots()
	assert_eq(slots.size(), InventoryStorage.INVENTORY_SIZE, "Should still have all slots")
	for slot: Dictionary in slots:
		assert_true(slot.is_empty(), "All slots should be empty")


func test_load_from_dict_handles_missing_slots_key() -> void:
	var data: Dictionary = {
		"version": 2
	}

	_storage._load_from_dict(data)

	var slots: Array[Dictionary] = _storage.get_slots()
	assert_eq(slots.size(), InventoryStorage.INVENTORY_SIZE, "Should still have all slots")


func test_load_from_dict_ignores_invalid_quantity() -> void:
	var data: Dictionary = {
		"version": 2,
		"slots": [
			{"item_id": "test", "quantity": 0},   # Zero quantity
			{"item_id": "test", "quantity": -5},  # Negative quantity
			{"item_id": "test", "quantity": 5}    # Valid
		]
	}

	_storage._load_from_dict(data)

	var slots: Array[Dictionary] = _storage.get_slots()
	assert_true(slots[0].is_empty(), "Zero quantity should be ignored")
	assert_true(slots[1].is_empty(), "Negative quantity should be ignored")
	assert_false(slots[2].is_empty(), "Valid quantity should be kept")


func test_load_from_dict_ignores_empty_item_id() -> void:
	var data: Dictionary = {
		"version": 2,
		"slots": [
			{"item_id": "", "quantity": 5},
			{"item_id": "valid", "quantity": 5}
		]
	}

	_storage._load_from_dict(data)

	var slots: Array[Dictionary] = _storage.get_slots()
	assert_true(slots[0].is_empty(), "Empty item_id should be ignored")
	assert_false(slots[1].is_empty(), "Valid item_id should be kept")


func test_load_from_dict_truncates_to_inventory_size() -> void:
	# Create data with more slots than INVENTORY_SIZE
	var slots_data: Array = []
	for i: int in range(50):  # More than 25
		slots_data.append({"item_id": "item_%d" % i, "quantity": 1})

	var data: Dictionary = {
		"version": 2,
		"slots": slots_data
	}

	_storage._load_from_dict(data)

	var slots: Array[Dictionary] = _storage.get_slots()
	assert_eq(slots.size(), InventoryStorage.INVENTORY_SIZE, "Should truncate to inventory size")


# =============================================================================
# Migration Tests
# =============================================================================

func test_migrate_item_id_converts_old_ids() -> void:
	var old_id: StringName = &"pearl"
	var new_id: StringName = _storage._migrate_item_id(old_id)

	assert_eq(new_id, &"air_pearl", "Should migrate 'pearl' to 'air_pearl'")


func test_migrate_item_id_preserves_unknown_ids() -> void:
	var unknown_id: StringName = &"unknown_item"
	var result: StringName = _storage._migrate_item_id(unknown_id)

	assert_eq(result, &"unknown_item", "Unknown IDs should pass through unchanged")


func test_migrate_item_id_preserves_current_ids() -> void:
	var current_id: StringName = &"air_pearl"
	var result: StringName = _storage._migrate_item_id(current_id)

	assert_eq(result, &"air_pearl", "Current IDs should pass through unchanged")


func test_load_from_dict_applies_migration() -> void:
	# Version 1 data with old "pearl" item ID
	var data: Dictionary = {
		"version": 1,
		"slots": [
			{"item_id": "pearl", "quantity": 10}
		]
	}

	_storage._load_from_dict(data)

	var slots: Array[Dictionary] = _storage.get_slots()
	assert_eq(slots[0].get("item_id"), &"air_pearl", "Should migrate 'pearl' to 'air_pearl'")
	assert_eq(slots[0].get("quantity"), 10, "Quantity should be preserved")


func test_load_from_dict_skips_migration_for_current_version() -> void:
	# Current version data - should not attempt migration
	var data: Dictionary = {
		"version": SteamCloudStorage.SAVE_VERSION,
		"slots": [
			{"item_id": "air_pearl", "quantity": 5}
		]
	}

	_storage._load_from_dict(data)

	var slots: Array[Dictionary] = _storage.get_slots()
	assert_eq(slots[0].get("item_id"), &"air_pearl", "Current version should not migrate")


func test_migration_table_exists() -> void:
	assert_true(
		SteamCloudStorage.ITEM_ID_MIGRATIONS.has(&"pearl"),
		"Migration table should have 'pearl' entry"
	)
	assert_eq(
		SteamCloudStorage.ITEM_ID_MIGRATIONS[&"pearl"],
		&"air_pearl",
		"'pearl' should migrate to 'air_pearl'"
	)


# =============================================================================
# Helper Function Tests: _get_slot_item_id
# =============================================================================

func test_get_slot_item_id_handles_stringname() -> void:
	var slot: Dictionary = {"item_id": &"test_item", "quantity": 5}
	var result: StringName = SteamCloudStorage._get_slot_item_id(slot)

	assert_eq(result, &"test_item", "Should extract StringName directly")


func test_get_slot_item_id_handles_string() -> void:
	var slot: Dictionary = {"item_id": "test_item", "quantity": 5}
	var result: StringName = SteamCloudStorage._get_slot_item_id(slot)

	assert_eq(result, &"test_item", "Should convert String to StringName")


func test_get_slot_item_id_handles_missing_key() -> void:
	var slot: Dictionary = {"quantity": 5}
	var result: StringName = SteamCloudStorage._get_slot_item_id(slot)

	assert_eq(result, &"", "Missing key should return empty StringName")


func test_get_slot_item_id_handles_empty_dict() -> void:
	var slot: Dictionary = {}
	var result: StringName = SteamCloudStorage._get_slot_item_id(slot)

	assert_eq(result, &"", "Empty dict should return empty StringName")


func test_get_slot_item_id_handles_invalid_type() -> void:
	var slot: Dictionary = {"item_id": 12345, "quantity": 5}
	var result: StringName = SteamCloudStorage._get_slot_item_id(slot)

	assert_eq(result, &"", "Invalid type should return empty StringName")


# =============================================================================
# Helper Function Tests: _get_slot_quantity
# =============================================================================

func test_get_slot_quantity_handles_int() -> void:
	var slot: Dictionary = {"item_id": &"test", "quantity": 42}
	var result: int = SteamCloudStorage._get_slot_quantity(slot)

	assert_eq(result, 42, "Should extract int directly")


func test_get_slot_quantity_handles_float() -> void:
	var slot: Dictionary = {"item_id": &"test", "quantity": 42.7}
	var result: int = SteamCloudStorage._get_slot_quantity(slot)

	assert_eq(result, 42, "Should convert float to int (truncate)")


func test_get_slot_quantity_handles_missing_key() -> void:
	var slot: Dictionary = {"item_id": &"test"}
	var result: int = SteamCloudStorage._get_slot_quantity(slot)

	assert_eq(result, 0, "Missing key should return 0")


func test_get_slot_quantity_handles_empty_dict() -> void:
	var slot: Dictionary = {}
	var result: int = SteamCloudStorage._get_slot_quantity(slot)

	assert_eq(result, 0, "Empty dict should return 0")


func test_get_slot_quantity_handles_invalid_type() -> void:
	var slot: Dictionary = {"item_id": &"test", "quantity": "not a number"}
	var result: int = SteamCloudStorage._get_slot_quantity(slot)

	assert_eq(result, 0, "Invalid type should return 0")


# =============================================================================
# Helper Function Tests: _extract_file_buffer
# =============================================================================

func test_extract_file_buffer_handles_packed_byte_array() -> void:
	var input: PackedByteArray = PackedByteArray([72, 101, 108, 108, 111])  # "Hello"
	var result: PackedByteArray = SteamCloudStorage._extract_file_buffer(input)

	assert_eq(result, input, "Should return PackedByteArray directly")


func test_extract_file_buffer_handles_dict_with_packed_byte_array() -> void:
	var buffer: PackedByteArray = PackedByteArray([72, 101, 108, 108, 111])
	var input: Dictionary = {"buf": buffer}
	var result: PackedByteArray = SteamCloudStorage._extract_file_buffer(input)

	assert_eq(result, buffer, "Should extract 'buf' from dictionary")


func test_extract_file_buffer_handles_dict_with_array() -> void:
	var input: Dictionary = {"buf": [72, 101, 108, 108, 111]}
	var result: PackedByteArray = SteamCloudStorage._extract_file_buffer(input)

	var expected: PackedByteArray = PackedByteArray([72, 101, 108, 108, 111])
	assert_eq(result, expected, "Should convert Array to PackedByteArray")


func test_extract_file_buffer_handles_dict_with_float_array() -> void:
	# JSON parsing might return floats
	var input: Dictionary = {"buf": [72.0, 101.0, 108.0, 108.0, 111.0]}
	var result: PackedByteArray = SteamCloudStorage._extract_file_buffer(input)

	var expected: PackedByteArray = PackedByteArray([72, 101, 108, 108, 111])
	assert_eq(result, expected, "Should convert float Array to PackedByteArray")


func test_extract_file_buffer_handles_empty_dict() -> void:
	var input: Dictionary = {}
	var result: PackedByteArray = SteamCloudStorage._extract_file_buffer(input)

	assert_true(result.is_empty(), "Empty dict should return empty buffer")


func test_extract_file_buffer_handles_dict_missing_buf() -> void:
	var input: Dictionary = {"other_key": "value"}
	var result: PackedByteArray = SteamCloudStorage._extract_file_buffer(input)

	assert_true(result.is_empty(), "Dict without 'buf' should return empty buffer")


func test_extract_file_buffer_handles_null() -> void:
	var input: Variant = null
	var result: PackedByteArray = SteamCloudStorage._extract_file_buffer(input)

	assert_true(result.is_empty(), "Null should return empty buffer")


func test_extract_file_buffer_handles_invalid_type() -> void:
	var input: String = "not a buffer"
	var result: PackedByteArray = SteamCloudStorage._extract_file_buffer(input)

	assert_true(result.is_empty(), "Invalid type should return empty buffer")


# =============================================================================
# Offline Behavior Tests
# =============================================================================

func test_load_inventory_without_steam_emits_success() -> void:
	# Skip if Steam is actually initialized
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	watch_signals(_storage)

	_storage.load_inventory()

	assert_signal_emitted(_storage, "load_completed", "Should emit load_completed")


func test_load_inventory_without_steam_initializes_empty() -> void:
	# Skip if Steam is actually initialized
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	_storage.load_inventory()

	var slots: Array[Dictionary] = _storage.get_slots()
	for slot: Dictionary in slots:
		assert_true(slot.is_empty(), "All slots should be empty without Steam")


# =============================================================================
# Constants Tests
# =============================================================================

func test_cloud_file_name_constant() -> void:
	assert_eq(SteamCloudStorage.CLOUD_FILE_NAME, "inventory.json", "Cloud file name should be correct")


func test_save_version_constant() -> void:
	assert_gt(SteamCloudStorage.SAVE_VERSION, 0, "Save version should be positive")
