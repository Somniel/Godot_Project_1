extends GutTest
## Tests for TownCloudStorage in-memory state management.
## Uses _initialize_empty() directly to avoid reading the real town_state.json
## when Steam is initialized in the editor.

var _storage: TownCloudStorage
var _timer_parent: Node


func before_each() -> void:
	_timer_parent = Node.new()
	add_child_autofree(_timer_parent)

	_storage = TownCloudStorage.new()
	_storage.setup(_timer_parent)
	# Don't call load_state() - it reads from Steam Cloud when Steam is active.
	# _init() already called _initialize_empty(), so we have a clean slate.
	_storage._is_new_town = true


func after_each() -> void:
	_cancel_pending_save()


func _cancel_pending_save() -> void:
	if _storage != null and _storage._save_timer != null:
		_storage._save_timer.stop()
	if _storage != null:
		_storage._save_pending = false


# =============================================================================
# Initial State
# =============================================================================

func test_new_storage_is_new_town() -> void:
	assert_true(_storage.is_new_town(), "Should be new town without Steam")


func test_new_storage_has_empty_town_name() -> void:
	assert_eq(_storage.get_town_name(), "")


func test_new_storage_has_4_default_gateways() -> void:
	for i: int in range(4):
		var gw: Dictionary = _storage.get_gateway(i)
		assert_eq(gw["id"], i, "Gateway %d should have correct id" % i)
		assert_eq(gw["link_type"], "none", "Gateway %d should be unlinked" % i)
		assert_eq(gw["linked_lobby_id"], "0", "Gateway %d lobby should be '0'" % i)
		assert_eq(gw["generation_seed"], 0, "Gateway %d seed should be 0" % i)
		assert_eq(gw["pearl_type"], "", "Gateway %d pearl should be empty" % i)
		assert_eq(gw["linked_gateway_id"], -1, "Gateway %d linked_gw should be -1" % i)


# =============================================================================
# Town Name
# =============================================================================

func test_set_town_name_and_get() -> void:
	_storage.set_town_name("My Town")
	assert_eq(_storage.get_town_name(), "My Town")


func test_set_empty_town_name() -> void:
	_storage.set_town_name("Test")
	_storage.set_town_name("")
	assert_eq(_storage.get_town_name(), "")


# =============================================================================
# Gateway CRUD
# =============================================================================

func test_set_gateway_config_stores_seed_and_pearl() -> void:
	_storage.set_gateway_config(0, 12345, "Flame Field", &"flame_pearl")
	var gw: Dictionary = _storage.get_gateway(0)
	assert_eq(gw["generation_seed"], 12345)
	assert_eq(gw["linked_map_name"], "Flame Field")
	assert_eq(gw["pearl_type"], "flame_pearl")
	assert_eq(gw["link_type"], "field")
	# Lobby should still be "0" (configured but not created)
	assert_eq(gw["linked_lobby_id"], "0")


func test_set_gateway_link_stores_lobby_id_as_string() -> void:
	_storage.set_gateway_link(1, 76561198012345678, "Far Field")
	var gw: Dictionary = _storage.get_gateway(1)
	# Lobby ID must be stored as string to preserve 64-bit precision
	assert_eq(gw["linked_lobby_id"], "76561198012345678")
	assert_eq(gw["linked_map_name"], "Far Field")
	assert_eq(gw["link_type"], "field")


func test_set_gateway_link_preserves_existing_config() -> void:
	# First: configure with seed and pearl type
	_storage.set_gateway_config(2, 99999, "Sky Field", &"air_pearl")
	# Then: set the lobby link
	_storage.set_gateway_link(2, 500, "Sky Field")

	var gw: Dictionary = _storage.get_gateway(2)
	assert_eq(gw["linked_lobby_id"], "500")
	# Config fields should survive the link update
	assert_eq(gw["generation_seed"], 99999, "Seed should be preserved")
	assert_eq(gw["pearl_type"], "air_pearl", "Pearl type should be preserved")


func test_clear_gateway_link_resets_to_none() -> void:
	_storage.set_gateway_link(0, 100, "Test Field")
	_storage.clear_gateway_link(0)

	var gw: Dictionary = _storage.get_gateway(0)
	assert_eq(gw["link_type"], "none")
	assert_eq(gw["linked_lobby_id"], "0")
	assert_eq(gw["linked_map_name"], "")
	assert_eq(gw["generation_seed"], 0)


func test_gateway_out_of_range_returns_defaults() -> void:
	var gw_neg: Dictionary = _storage.get_gateway(-1)
	assert_eq(gw_neg["link_type"], "none", "Negative index should return defaults")
	assert_eq(gw_neg["id"], -1)

	var gw_high: Dictionary = _storage.get_gateway(4)
	assert_eq(gw_high["link_type"], "none", "Index 4 should return defaults")
	assert_eq(gw_high["id"], 4)


func test_set_gateway_config_with_linked_gateway_id() -> void:
	_storage.set_gateway_config(3, 55555, "Test", &"life_pearl", 2)
	var gw: Dictionary = _storage.get_gateway(3)
	assert_eq(gw["linked_gateway_id"], 2, "linked_gateway_id should be stored")


func test_set_gateway_link_with_linked_gateway_id() -> void:
	_storage.set_gateway_config(1, 11111, "Aqua Field", &"water_pearl", 0)
	_storage.set_gateway_link(1, 300, "Aqua Field", 3)
	var gw: Dictionary = _storage.get_gateway(1)
	assert_eq(gw["linked_gateway_id"], 3, "Explicit linked_gateway_id should override")


func test_set_gateway_link_preserves_linked_gateway_id() -> void:
	_storage.set_gateway_config(0, 22222, "Test Field", &"flame_pearl", 1)
	# Link without specifying linked_gateway_id (-1 means "keep existing")
	_storage.set_gateway_link(0, 400, "Test Field")
	var gw: Dictionary = _storage.get_gateway(0)
	assert_eq(gw["linked_gateway_id"], 1, "Should preserve existing linked_gateway_id")


# =============================================================================
# Linked Fields
# =============================================================================

func test_set_linked_field_and_get() -> void:
	var items: Array[Dictionary] = [
		{"item_id": "flame_pearl", "quantity": 2},
	]
	var gws: Array[Dictionary] = [
		{"id": 0, "link_type": "none"},
	]
	_storage.set_linked_field(42, &"flame_pearl", items, gws)

	var result: Variant = _storage.get_linked_field(42)
	assert_not_null(result, "Should return field data")

	var data: Dictionary = result
	assert_eq(data["pearl_type"], "flame_pearl")
	assert_eq(data["items"].size(), 1)
	assert_eq(data["gateways"].size(), 1)


func test_has_linked_field_true() -> void:
	var items: Array[Dictionary] = []
	var gws: Array[Dictionary] = []
	_storage.set_linked_field(99, &"", items, gws)
	assert_true(_storage.has_linked_field(99))


func test_has_linked_field_false() -> void:
	assert_false(_storage.has_linked_field(99999))


func test_get_linked_field_returns_deep_copy() -> void:
	var items: Array[Dictionary] = [{"item_id": "pearl", "quantity": 5}]
	var gws: Array[Dictionary] = []
	_storage.set_linked_field(50, &"air_pearl", items, gws)

	var copy: Variant = _storage.get_linked_field(50)
	assert_not_null(copy)
	# Mutate the returned copy
	var copy_dict: Dictionary = copy
	copy_dict["pearl_type"] = "MUTATED"

	# Original should be unchanged
	var original: Variant = _storage.get_linked_field(50)
	var original_dict: Dictionary = original
	assert_eq(original_dict["pearl_type"], "air_pearl", "Original should be unchanged")


func test_get_linked_field_returns_null_when_missing() -> void:
	assert_null(_storage.get_linked_field(777))


func test_remove_linked_field() -> void:
	var items: Array[Dictionary] = []
	var gws: Array[Dictionary] = []
	_storage.set_linked_field(60, &"", items, gws)
	_storage.remove_linked_field(60)
	assert_false(_storage.has_linked_field(60))


func test_set_linked_field_stores_version_and_modifier() -> void:
	var items: Array[Dictionary] = []
	var gws: Array[Dictionary] = []
	_storage.set_linked_field(70, &"water_pearl", items, gws, 5, 76561198012345678)

	var data: Dictionary = _storage.get_linked_field(70)
	assert_eq(data["state_version"], 5)
	assert_eq(data["last_modified_by"], 76561198012345678)


func test_set_linked_field_auto_increments_version() -> void:
	var items: Array[Dictionary] = []
	var gws: Array[Dictionary] = []
	# First save: version not specified, should start at 1
	_storage.set_linked_field(80, &"", items, gws)
	var data1: Dictionary = _storage.get_linked_field(80)
	assert_eq(data1["state_version"], 1)

	# Second save: should auto-increment to 2
	_storage.set_linked_field(80, &"", items, gws)
	var data2: Dictionary = _storage.get_linked_field(80)
	assert_eq(data2["state_version"], 2)


# =============================================================================
# Orphan Cleanup
# =============================================================================

func test_cleanup_orphaned_linked_fields_removes_unreferenced() -> void:
	var items: Array[Dictionary] = []
	var gws: Array[Dictionary] = []
	# Add a linked field with seed 999 (not referenced by any gateway)
	_storage.set_linked_field(999, &"", items, gws)
	assert_true(_storage.has_linked_field(999))

	_storage.cleanup_orphaned_linked_fields()
	assert_false(_storage.has_linked_field(999), "Unreferenced field should be removed")


func test_cleanup_orphaned_linked_fields_preserves_referenced() -> void:
	# Configure gateway 0 with seed 555
	_storage.set_gateway_config(0, 555, "Test Field", &"flame_pearl")
	# Add linked field with matching seed
	var items: Array[Dictionary] = [{"item_id": "flame_pearl", "quantity": 1}]
	var gws: Array[Dictionary] = []
	_storage.set_linked_field(555, &"flame_pearl", items, gws)

	_storage.cleanup_orphaned_linked_fields()
	assert_true(_storage.has_linked_field(555), "Referenced field should survive")


# =============================================================================
# Entities
# =============================================================================

func test_add_entity_and_get() -> void:
	_storage.add_entity({"type": "tree", "x": 5, "y": 0})
	var entities: Array = _storage.get_entities()
	assert_eq(entities.size(), 1)
	assert_eq(entities[0]["type"], "tree")


func test_remove_entity_by_criteria() -> void:
	_storage.add_entity({"type": "tree", "id": 1})
	_storage.add_entity({"type": "rock", "id": 2})
	var removed: bool = _storage.remove_entity({"type": "tree"})
	assert_true(removed, "Should return true on match")
	var entities: Array = _storage.get_entities()
	assert_eq(entities.size(), 1)
	assert_eq(entities[0]["type"], "rock")


func test_remove_entity_returns_false_when_not_found() -> void:
	_storage.add_entity({"type": "tree"})
	var removed: bool = _storage.remove_entity({"type": "dragon"})
	assert_false(removed, "Should return false when no match")


func test_set_entities_replaces_all() -> void:
	_storage.add_entity({"type": "old"})
	_storage.set_entities([{"type": "new_a"}, {"type": "new_b"}])
	var entities: Array = _storage.get_entities()
	assert_eq(entities.size(), 2)
	assert_eq(entities[0]["type"], "new_a")


# =============================================================================
# _load_from_dict Migration
# =============================================================================

func test_load_from_dict_valid_v4() -> void:
	var data: Dictionary = {
		"version": 4,
		"town_name": "TestTown",
		"last_saved": "2025-01-01T00:00:00",
		"gateways": [
			{
				"id": 0, "link_type": "field", "linked_lobby_id": "12345",
				"linked_map_name": "Field A", "generation_seed": 111,
				"pearl_type": "flame_pearl", "linked_gateway_id": 2
			},
			{
				"id": 1, "link_type": "none", "linked_lobby_id": "0",
				"linked_map_name": "", "generation_seed": 0,
				"pearl_type": "", "linked_gateway_id": -1
			},
			{
				"id": 2, "link_type": "none", "linked_lobby_id": "0",
				"linked_map_name": "", "generation_seed": 0,
				"pearl_type": "", "linked_gateway_id": -1
			},
			{
				"id": 3, "link_type": "none", "linked_lobby_id": "0",
				"linked_map_name": "", "generation_seed": 0,
				"pearl_type": "", "linked_gateway_id": -1
			}
		],
		"linked_fields": {},
		"entities": [],
		"modifications": []
	}
	_storage._load_from_dict(data)

	assert_eq(_storage.get_town_name(), "TestTown")
	var gw0: Dictionary = _storage.get_gateway(0)
	assert_eq(gw0["link_type"], "field")
	assert_eq(gw0["linked_lobby_id"], "12345")
	assert_eq(gw0["generation_seed"], 111)
	assert_eq(gw0["pearl_type"], "flame_pearl")
	assert_eq(gw0["linked_gateway_id"], 2)


func test_load_from_dict_upgrades_missing_fields() -> void:
	# Simulate v1-style data: no pearl_type, no linked_gateway_id, no link_type
	var data: Dictionary = {
		"version": 1,
		"town_name": "OldTown",
		"gateways": [
			{
				"id": 0, "linked_lobby_id": "0",
				"linked_map_name": "Field A", "generation_seed": 555
			},
			{
				"id": 1, "linked_lobby_id": "0",
				"linked_map_name": "", "generation_seed": 0
			}
		]
	}
	_storage._load_from_dict(data)

	var gw0: Dictionary = _storage.get_gateway(0)
	# Should have defaults filled in
	assert_eq(gw0["pearl_type"], "", "Should default pearl_type to empty")
	assert_eq(gw0["linked_gateway_id"], -1, "Should default linked_gateway_id to -1")
	# link_type should be inferred: seed > 0 means "field"
	assert_eq(gw0["link_type"], "field", "Should infer link_type from seed")

	var gw1: Dictionary = _storage.get_gateway(1)
	assert_eq(gw1["link_type"], "none", "Seed 0 should be 'none'")

	# Gateways 2 and 3 were missing, should have defaults
	var gw2: Dictionary = _storage.get_gateway(2)
	assert_eq(gw2["link_type"], "none")
	assert_eq(gw2["generation_seed"], 0)


func test_load_from_dict_lobby_id_int_to_string_migration() -> void:
	# Old format stored linked_lobby_id as integer
	var data: Dictionary = {
		"version": 2,
		"town_name": "MigrateTown",
		"gateways": [
			{
				"id": 0, "linked_lobby_id": 42,
				"linked_map_name": "Field", "generation_seed": 100
			}
		]
	}
	_storage._load_from_dict(data)

	var gw0: Dictionary = _storage.get_gateway(0)
	# Should be migrated to string
	assert_eq(gw0["linked_lobby_id"], "42", "Int lobby ID should be migrated to string")
