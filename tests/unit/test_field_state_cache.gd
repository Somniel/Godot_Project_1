extends GutTest
## Tests for FieldStateCache: CRDT 2P-Set caching, set-union merge, validation.

var _cache: FieldStateCache


func before_each() -> void:
	_cache = FieldStateCache.new()


# =============================================================================
# Helpers
# =============================================================================


func _make_removed(count: int = 2, seed_val: int = 42) -> Dictionary:
	var removed: Dictionary = {}
	for i: int in range(count):
		var iid: String = "gen_%d_%d" % [seed_val, i]
		removed[iid] = {
			"field_lobby_id": 100, "field_host_steam_id": 5000, "timestamp": 1700000000 + i
		}
	return removed


func _make_placed(count: int = 1) -> Dictionary:
	var placed: Dictionary = {}
	for i: int in range(count):
		var iid: String = "placed_5000_%d_%d" % [1700000000, i]
		placed[iid] = {
			"instance_id": iid,
			"item_id": "water_pearl",
			"position": {"x": float(i), "y": 0.0, "z": 0.0},
			"quantity": 1,
			"field_lobby_id": 100,
			"field_host_steam_id": 5000,
			"timestamp": 1700000000 + i
		}
	return placed


func _make_gateways(count: int = 1) -> Array[Dictionary]:
	var gws: Array[Dictionary] = []
	for i: int in range(count):
		gws.append({"id": i, "link_type": "none", "linked_lobby_id": 0})
	return gws


func _cache_default(
	lobby_id: int = 100,
	seed_val: int = 42,
	removed: Dictionary = {},
	placed: Dictionary = {},
	gw_versions: Array[int] = [0, 0, 0, 0],
	modifier: int = 0
) -> void:
	_cache.cache_field(
		lobby_id,
		seed_val,
		200,
		0,
		"Town",
		&"flame_pearl",
		removed,
		placed,
		gw_versions,
		_make_gateways(),
		modifier
	)


func _make_merge_data(
	lobby_id: int = 100,
	seed_val: int = 42,
	removed: Dictionary = {},
	placed: Dictionary = {},
	gw_versions: Array = [0, 0, 0, 0],
	gateways: Array = []
) -> Dictionary:
	return {
		"lobby_id": lobby_id,
		"generation_seed": seed_val,
		"origin_lobby_id": 200,
		"origin_gateway": 0,
		"origin_map_name": "Town",
		"pearl_type": "flame_pearl",
		"last_modified": "",
		"last_modified_by": 0,
		"removed_items": removed,
		"placed_items": placed,
		"gateway_versions": gw_versions,
		"gateways": gateways
	}


# =============================================================================
# Basic CRUD
# =============================================================================


func test_cache_field_stores_crdt_state() -> void:
	var removed: Dictionary = _make_removed()
	var placed: Dictionary = _make_placed()
	var gws: Array[Dictionary] = _make_gateways(2)
	_cache.cache_field(100, 42, 200, 0, "Town", &"flame_pearl", removed, placed, [1, 0, 0, 0], gws)

	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_not_null(state, "State should be cached")
	assert_eq(state.generation_seed, 42)
	assert_eq(state.origin_lobby_id, 200)
	assert_eq(state.origin_map_name, "Town")
	assert_eq(state.pearl_type, &"flame_pearl")
	assert_eq(state.removed_items.size(), 2)
	assert_eq(state.placed_items.size(), 1)
	assert_eq(state.gateway_versions[0], 1)
	assert_eq(state.gateways.size(), 2)


func test_has_cached_state_true_after_cache() -> void:
	_cache_default()
	assert_true(_cache.has_cached_state(100))


func test_has_cached_state_false_when_empty() -> void:
	assert_false(_cache.has_cached_state(999))


func test_get_cached_state_returns_null_when_missing() -> void:
	assert_null(_cache.get_cached_state(999))


func test_remove_cached_state() -> void:
	_cache_default()
	_cache.remove_cached_state(100)
	assert_false(_cache.has_cached_state(100))


func test_clear_all() -> void:
	_cache_default(100)
	_cache_default(200, 43)
	_cache_default(300, 44)
	_cache.clear_all()
	assert_false(_cache.has_cached_state(100))
	assert_false(_cache.has_cached_state(200))
	assert_false(_cache.has_cached_state(300))


func test_get_cached_lobby_ids() -> void:
	_cache_default(10, 1)
	_cache_default(20, 2)
	var ids: Array[int] = _cache.get_cached_lobby_ids()
	assert_eq(ids.size(), 2, "Should have 2 IDs")
	assert_true(10 in ids, "Should contain 10")
	assert_true(20 in ids, "Should contain 20")


func test_cache_stores_deep_copy() -> void:
	var removed: Dictionary = _make_removed(1)
	_cache_default(100, 42, removed)

	# Mutate original
	removed["gen_42_999"] = {"field_lobby_id": 0, "field_host_steam_id": 0, "timestamp": 0}

	# Cache should not be affected
	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_eq(state.removed_items.size(), 1, "Cache should hold a deep copy")


# =============================================================================
# CRDT Merge: Set Union
# =============================================================================


func test_merge_unions_removed_items() -> void:
	# Local has gen_42_0
	var local_removed: Dictionary = {
		"gen_42_0": {"field_lobby_id": 100, "field_host_steam_id": 5000, "timestamp": 1}
	}
	_cache_default(100, 42, local_removed)

	# Incoming has gen_42_1
	var incoming_removed: Dictionary = {
		"gen_42_1": {"field_lobby_id": 200, "field_host_steam_id": 6000, "timestamp": 2}
	}
	var data: Dictionary = _make_merge_data(100, 42, incoming_removed)

	@warning_ignore("return_value_discarded")
	_cache.merge_entry(data)

	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_true(state.removed_items.has("gen_42_0"), "Local removal preserved")
	assert_true(state.removed_items.has("gen_42_1"), "Incoming removal added")
	assert_eq(state.removed_items.size(), 2, "Union should have both")


func test_merge_unions_placed_items() -> void:
	# Local has one placed item
	var local_placed: Dictionary = {
		"placed_5000_1_0":
		{
			"instance_id": "placed_5000_1_0",
			"item_id": "flame_pearl",
			"position": {"x": 1.0, "y": 0.0, "z": 0.0},
			"quantity": 1,
			"field_lobby_id": 100,
			"field_host_steam_id": 5000,
			"timestamp": 1
		}
	}
	_cache_default(100, 42, {}, local_placed)

	# Incoming has a different placed item
	var incoming_placed: Dictionary = {
		"placed_6000_2_0":
		{
			"instance_id": "placed_6000_2_0",
			"item_id": "water_pearl",
			"position": {"x": 3.0, "y": 0.0, "z": 0.0},
			"quantity": 1,
			"field_lobby_id": 200,
			"field_host_steam_id": 6000,
			"timestamp": 2
		}
	}
	var data: Dictionary = _make_merge_data(100, 42, {}, incoming_placed)

	@warning_ignore("return_value_discarded")
	_cache.merge_entry(data)

	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_true(state.placed_items.has("placed_5000_1_0"), "Local placed preserved")
	assert_true(state.placed_items.has("placed_6000_2_0"), "Incoming placed added")
	assert_eq(state.placed_items.size(), 2, "Union should have both")


func test_merge_is_commutative() -> void:
	# Merge(A, B) should equal Merge(B, A)
	var removed_a: Dictionary = {
		"gen_42_0": {"field_lobby_id": 1, "field_host_steam_id": 1, "timestamp": 1}
	}
	var removed_b: Dictionary = {
		"gen_42_1": {"field_lobby_id": 2, "field_host_steam_id": 2, "timestamp": 2}
	}

	# Order 1: cache A, merge B
	var cache1 := FieldStateCache.new()
	cache1.cache_field(100, 42, 0, 0, "", &"", removed_a, {}, [0, 0, 0, 0], [])
	@warning_ignore("return_value_discarded")
	cache1.merge_entry(_make_merge_data(100, 42, removed_b))

	# Order 2: cache B, merge A
	var cache2 := FieldStateCache.new()
	cache2.cache_field(100, 42, 0, 0, "", &"", removed_b, {}, [0, 0, 0, 0], [])
	@warning_ignore("return_value_discarded")
	cache2.merge_entry(_make_merge_data(100, 42, removed_a))

	var s1: FieldStateCache.FieldState = cache1.get_cached_state(100)
	var s2: FieldStateCache.FieldState = cache2.get_cached_state(100)

	assert_eq(s1.removed_items.size(), s2.removed_items.size(), "Same size")
	assert_true(s1.removed_items.has("gen_42_0"), "Both have gen_42_0")
	assert_true(s1.removed_items.has("gen_42_1"), "Both have gen_42_1")
	assert_true(s2.removed_items.has("gen_42_0"), "Both have gen_42_0")
	assert_true(s2.removed_items.has("gen_42_1"), "Both have gen_42_1")


func test_merge_is_idempotent() -> void:
	# Merge(A, A) should equal A
	var removed: Dictionary = {
		"gen_42_0": {"field_lobby_id": 1, "field_host_steam_id": 1, "timestamp": 1}
	}
	_cache_default(100, 42, removed)

	var data: Dictionary = _make_merge_data(100, 42, removed)
	@warning_ignore("return_value_discarded")
	_cache.merge_entry(data)
	@warning_ignore("return_value_discarded")
	_cache.merge_entry(data)

	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_eq(state.removed_items.size(), 1, "Should remain 1 after double merge")
	assert_true(state.removed_items.has("gen_42_0"))


func test_merge_gateway_higher_version_wins() -> void:
	# Local has gateway_versions [1, 0, 0, 0]
	_cache.cache_field(
		100,
		42,
		0,
		0,
		"",
		&"",
		{},
		{},
		[1, 0, 3, 0],
		[{"id": 0, "link_type": "field", "linked_lobby_id": 50}]
	)

	# Incoming has [0, 2, 0, 5]
	var data: Dictionary = _make_merge_data(100, 42, {}, {}, [0, 2, 0, 5])

	@warning_ignore("return_value_discarded")
	_cache.merge_entry(data)

	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	# Per-slot max: [max(1,0), max(0,2), max(3,0), max(0,5)] = [1, 2, 3, 5]
	assert_eq(state.gateway_versions[0], 1, "Slot 0: local higher")
	assert_eq(state.gateway_versions[1], 2, "Slot 1: incoming higher")
	assert_eq(state.gateway_versions[2], 3, "Slot 2: local higher")
	assert_eq(state.gateway_versions[3], 5, "Slot 3: incoming higher")


func test_merge_new_lobby_always_accepted() -> void:
	var removed: Dictionary = {
		"gen_99_0": {"field_lobby_id": 1, "field_host_steam_id": 1, "timestamp": 1}
	}
	var data: Dictionary = _make_merge_data(500, 99, removed)

	var result: bool = _cache.merge_entry(data)
	assert_true(result, "New lobby should always be accepted")
	assert_true(_cache.has_cached_state(500))

	var state: FieldStateCache.FieldState = _cache.get_cached_state(500)
	assert_eq(state.generation_seed, 99)
	assert_eq(state.removed_items.size(), 1)


func test_merge_entry_always_returns_true() -> void:
	# CRDT merge never rejects — it only grows
	_cache_default(100, 42, _make_removed())

	var data: Dictionary = _make_merge_data(100, 42)
	var result: bool = _cache.merge_entry(data)
	assert_true(result, "CRDT merge should always return true")


func test_merge_entries_batch() -> void:
	var entries: Array = [
		_make_merge_data(
			10, 1, {"gen_1_0": {"field_lobby_id": 0, "field_host_steam_id": 0, "timestamp": 0}}
		),
		_make_merge_data(
			20, 2, {"gen_2_0": {"field_lobby_id": 0, "field_host_steam_id": 0, "timestamp": 0}}
		)
	]
	_cache.merge_entries(entries)
	assert_true(_cache.has_cached_state(10))
	assert_true(_cache.has_cached_state(20))


func test_merge_preserves_first_write_for_same_key() -> void:
	# First-write wins: if local already has the key, incoming value is ignored
	var local_removed: Dictionary = {
		"gen_42_0": {"field_lobby_id": 100, "field_host_steam_id": 5000, "timestamp": 1}
	}
	_cache_default(100, 42, local_removed)

	var incoming_removed: Dictionary = {
		"gen_42_0": {"field_lobby_id": 999, "field_host_steam_id": 9999, "timestamp": 999}
	}
	var data: Dictionary = _make_merge_data(100, 42, incoming_removed)
	@warning_ignore("return_value_discarded")
	_cache.merge_entry(data)

	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	var entry: Dictionary = state.removed_items["gen_42_0"]
	assert_eq(entry["field_lobby_id"], 100, "First write should win")


# =============================================================================
# Validation
# =============================================================================


func test_is_valid_instance_id_gen_format() -> void:
	assert_true(FieldStateCache.is_valid_instance_id("gen_42_0"))
	assert_true(FieldStateCache.is_valid_instance_id("gen_99999_100"))


func test_is_valid_instance_id_placed_format() -> void:
	assert_true(FieldStateCache.is_valid_instance_id("placed_5000_1700000000_0"))
	assert_true(FieldStateCache.is_valid_instance_id("placed_123_456_789"))


func test_is_valid_instance_id_migrated_format() -> void:
	assert_true(FieldStateCache.is_valid_instance_id("migrated_42_0"))


func test_is_valid_instance_id_rejects_invalid() -> void:
	assert_false(FieldStateCache.is_valid_instance_id(""))
	assert_false(FieldStateCache.is_valid_instance_id("random_string"))
	assert_false(FieldStateCache.is_valid_instance_id("gen_"))
	assert_false(FieldStateCache.is_valid_instance_id("gen_abc_0"))
	assert_false(FieldStateCache.is_valid_instance_id("placed_5000_1700000000"))


func test_is_valid_placed_entry_valid() -> void:
	var entry: Dictionary = {
		"instance_id": "placed_5000_1_0",
		"item_id": "water_pearl",
		"position": {"x": 5.0, "y": 0.0, "z": -3.0},
		"quantity": 1
	}
	assert_true(FieldStateCache.is_valid_placed_entry(entry))


func test_is_valid_placed_entry_rejects_missing_fields() -> void:
	# Missing item_id
	var entry: Dictionary = {
		"instance_id": "placed_5000_1_0", "position": {"x": 0.0, "y": 0.0, "z": 0.0}, "quantity": 1
	}
	assert_false(FieldStateCache.is_valid_placed_entry(entry))


func test_is_valid_placed_entry_rejects_bad_quantity() -> void:
	var entry: Dictionary = {
		"instance_id": "placed_5000_1_0",
		"item_id": "water_pearl",
		"position": {"x": 0.0, "y": 0.0, "z": 0.0},
		"quantity": 0
	}
	assert_false(FieldStateCache.is_valid_placed_entry(entry))


func test_is_valid_placed_entry_rejects_out_of_bounds_position() -> void:
	var entry: Dictionary = {
		"instance_id": "placed_5000_1_0",
		"item_id": "water_pearl",
		"position": {"x": 50.0, "y": 0.0, "z": 0.0},
		"quantity": 1
	}
	assert_false(FieldStateCache.is_valid_placed_entry(entry))


func test_merge_rejects_invalid_instance_id() -> void:
	_cache_default(100, 42)

	# Incoming has invalid instance_id key
	var invalid_removed: Dictionary = {
		"INVALID_KEY": {"field_lobby_id": 1, "field_host_steam_id": 1, "timestamp": 1}
	}
	var data: Dictionary = _make_merge_data(100, 42, invalid_removed)
	@warning_ignore("return_value_discarded")
	_cache.merge_entry(data)

	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_false(
		state.removed_items.has("INVALID_KEY"), "Invalid instance ID should be filtered out"
	)
	# push_warning is tracked as engine error in editor but not headless;
	# mark any tracked errors as handled so neither environment fails.
	for err: Variant in get_errors():
		err.handled = true


func test_merge_rejects_invalid_placed_entry() -> void:
	_cache_default(100, 42)

	# Incoming placed item with out-of-bounds position
	var invalid_placed: Dictionary = {
		"placed_5000_1_0":
		{
			"instance_id": "placed_5000_1_0",
			"item_id": "water_pearl",
			"position": {"x": 100.0, "y": 0.0, "z": 0.0},
			"quantity": 1
		}
	}
	var data: Dictionary = _make_merge_data(100, 42, {}, invalid_placed)
	@warning_ignore("return_value_discarded")
	_cache.merge_entry(data)

	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_false(
		state.placed_items.has("placed_5000_1_0"), "Out-of-bounds placement should be filtered"
	)
	# push_warning is tracked as engine error in editor but not headless;
	# mark any tracked errors as handled so neither environment fails.
	for err: Variant in get_errors():
		err.handled = true


func test_action_metadata_preserved_through_roundtrip() -> void:
	var removed: Dictionary = {
		"gen_42_0":
		{"field_lobby_id": 500, "field_host_steam_id": 76561198012345678, "timestamp": 1706745600}
	}
	var placed: Dictionary = {
		"placed_765_1706745600_0":
		{
			"instance_id": "placed_765_1706745600_0",
			"item_id": "water_pearl",
			"position": {"x": 5.0, "y": 0.0, "z": -3.0},
			"quantity": 1,
			"field_lobby_id": 500,
			"field_host_steam_id": 76561198012345678,
			"timestamp": 1706745600
		}
	}
	_cache.cache_field(
		100,
		42,
		200,
		0,
		"Town",
		&"flame_pearl",
		removed,
		placed,
		[0, 0, 0, 0],
		_make_gateways(),
		7777
	)

	# Serialize and merge into fresh cache
	var serialized: Dictionary = _cache.serialize_entry(100)
	var cache2 := FieldStateCache.new()
	@warning_ignore("return_value_discarded")
	cache2.merge_entry(serialized)

	var state: FieldStateCache.FieldState = cache2.get_cached_state(100)
	assert_not_null(state)

	# Check removed action metadata
	var rem_entry: Dictionary = state.removed_items["gen_42_0"]
	assert_eq(rem_entry["field_lobby_id"], 500)
	assert_eq(rem_entry["field_host_steam_id"], 76561198012345678)
	assert_eq(rem_entry["timestamp"], 1706745600)

	# Check placed action metadata
	var plc_entry: Dictionary = state.placed_items["placed_765_1706745600_0"]
	assert_eq(plc_entry["field_lobby_id"], 500)
	assert_eq(plc_entry["field_host_steam_id"], 76561198012345678)
	assert_eq(plc_entry["timestamp"], 1706745600)
	assert_eq(plc_entry["item_id"], "water_pearl")
	assert_eq(plc_entry["quantity"], 1)


# =============================================================================
# Serialization
# =============================================================================


func test_serialize_entry_roundtrip() -> void:
	var removed: Dictionary = _make_removed(3)
	var placed: Dictionary = _make_placed(2)
	var gws: Array[Dictionary] = _make_gateways(2)
	_cache.cache_field(
		100, 42, 200, 1, "Origin", &"air_pearl", removed, placed, [1, 2, 0, 0], gws, 7777
	)

	var serialized: Dictionary = _cache.serialize_entry(100)
	assert_false(serialized.is_empty(), "Should serialize non-empty")
	assert_eq(serialized["lobby_id"], 100)
	assert_eq(serialized["generation_seed"], 42)
	assert_eq(serialized["pearl_type"], "air_pearl")

	# Merge into a fresh cache
	var cache2 := FieldStateCache.new()
	@warning_ignore("return_value_discarded")
	cache2.merge_entry(serialized)

	var state: FieldStateCache.FieldState = cache2.get_cached_state(100)
	assert_not_null(state)
	assert_eq(state.generation_seed, 42)
	assert_eq(state.origin_lobby_id, 200)
	assert_eq(state.origin_gateway, 1)
	assert_eq(state.origin_map_name, "Origin")
	assert_eq(state.pearl_type, &"air_pearl")
	assert_eq(state.removed_items.size(), 3)
	assert_eq(state.placed_items.size(), 2)
	assert_eq(state.gateways.size(), 2)


func test_serialize_all_includes_all_entries() -> void:
	_cache_default(10, 1)
	_cache_default(20, 2)
	_cache_default(30, 3)
	var entries: Array[Dictionary] = _cache.serialize_all()
	assert_eq(entries.size(), 3)


func test_serialize_entry_returns_empty_for_unknown_lobby() -> void:
	var result: Dictionary = _cache.serialize_entry(999)
	assert_true(result.is_empty(), "Should return empty dict for unknown lobby")


# =============================================================================
# Orphan Cleanup
# =============================================================================


func test_cleanup_orphaned_fields_removes_unlinked() -> void:
	_cache_default(100, 1)
	_cache_default(200, 2)
	_cache_default(300, 3)

	# Only 200 is linked
	var linked: Array[int] = [200]
	_cache.cleanup_orphaned_fields(linked)

	assert_false(_cache.has_cached_state(100), "100 should be removed")
	assert_true(_cache.has_cached_state(200), "200 should survive")
	assert_false(_cache.has_cached_state(300), "300 should be removed")


func test_cleanup_orphaned_fields_preserves_linked() -> void:
	_cache_default(100, 1)
	_cache_default(200, 2)

	var linked: Array[int] = [100, 200]
	_cache.cleanup_orphaned_fields(linked)

	assert_true(_cache.has_cached_state(100))
	assert_true(_cache.has_cached_state(200))


# =============================================================================
# Field Type Metadata
# =============================================================================


func test_cache_field_stores_field_type() -> void:
	_cache.cache_field(
		100, 42, 200, 0, "Town", &"flame_pearl", {}, {}, [0, 0, 0, 0], [], 0, "linked"
	)
	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_eq(state.field_type, "linked", "Field type should be stored")


func test_cache_field_defaults_field_type_to_empty() -> void:
	_cache_default(100)
	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_eq(state.field_type, "", "Field type should default to empty string")


func test_field_type_survives_serialization_roundtrip() -> void:
	_cache.cache_field(100, 42, 200, 1, "Origin", &"air_pearl", {}, {}, [0, 0, 0, 0], [], 0, "deep")
	var serialized: Dictionary = _cache.serialize_entry(100)
	assert_eq(serialized["field_type"], "deep", "Serialized data should include field_type")

	# Merge into fresh cache
	var cache2 := FieldStateCache.new()
	@warning_ignore("return_value_discarded")
	cache2.merge_entry(serialized)

	var state: FieldStateCache.FieldState = cache2.get_cached_state(100)
	assert_eq(state.field_type, "deep", "Field type should survive roundtrip")


func test_merge_new_entry_preserves_field_type() -> void:
	var data: Dictionary = _make_merge_data(100, 42)
	data["field_type"] = "linked"

	@warning_ignore("return_value_discarded")
	_cache.merge_entry(data)

	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_eq(state.field_type, "linked", "Merged new entry should preserve field_type")


func test_merge_missing_field_type_defaults_to_empty() -> void:
	# _make_merge_data does not include field_type key
	var data: Dictionary = _make_merge_data(100, 42)

	@warning_ignore("return_value_discarded")
	_cache.merge_entry(data)

	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_eq(state.field_type, "", "Missing field_type should default to empty")
