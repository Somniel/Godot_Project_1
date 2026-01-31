extends GutTest
## Tests for FieldStateCache: CRUD, version tracking, merge tiebreaking, serialization.

var _cache: FieldStateCache


func before_each() -> void:
	_cache = FieldStateCache.new()


# =============================================================================
# Helper
# =============================================================================

func _make_items(count: int = 2) -> Array[Dictionary]:
	var items: Array[Dictionary] = []
	for i: int in range(count):
		items.append({"item_id": "pearl_%d" % i, "position": Vector3(i, 0, 0), "quantity": 1})
	return items


func _make_gateways(count: int = 1) -> Array[Dictionary]:
	var gws: Array[Dictionary] = []
	for i: int in range(count):
		gws.append({"id": i, "link_type": "none", "linked_lobby_id": 0})
	return gws


# =============================================================================
# Basic CRUD
# =============================================================================

func test_cache_field_stores_state() -> void:
	var items: Array[Dictionary] = _make_items()
	var gws: Array[Dictionary] = _make_gateways()
	_cache.cache_field(100, 42, 200, 0, "Town", &"flame_pearl", items, gws)

	var state: FieldStateCache.FieldState = _cache.get_cached_state(100)
	assert_not_null(state, "State should be cached")
	assert_eq(state.generation_seed, 42)
	assert_eq(state.origin_lobby_id, 200)
	assert_eq(state.origin_map_name, "Town")
	assert_eq(state.pearl_type, &"flame_pearl")
	assert_eq(state.items.size(), 2)
	assert_eq(state.gateways.size(), 1)


func test_has_cached_state_true_after_cache() -> void:
	_cache.cache_field(100, 42, 200, 0, "Town", &"", _make_items(), _make_gateways())
	assert_true(_cache.has_cached_state(100))


func test_has_cached_state_false_when_empty() -> void:
	assert_false(_cache.has_cached_state(999))


func test_get_cached_state_returns_null_when_missing() -> void:
	assert_null(_cache.get_cached_state(999))


func test_remove_cached_state() -> void:
	_cache.cache_field(100, 42, 200, 0, "", &"", _make_items(), _make_gateways())
	_cache.remove_cached_state(100)
	assert_false(_cache.has_cached_state(100))


func test_clear_all() -> void:
	_cache.cache_field(100, 1, 0, 0, "", &"", _make_items(), _make_gateways())
	_cache.cache_field(200, 2, 0, 0, "", &"", _make_items(), _make_gateways())
	_cache.cache_field(300, 3, 0, 0, "", &"", _make_items(), _make_gateways())
	_cache.clear_all()
	assert_false(_cache.has_cached_state(100))
	assert_false(_cache.has_cached_state(200))
	assert_false(_cache.has_cached_state(300))


func test_get_cached_lobby_ids() -> void:
	_cache.cache_field(10, 1, 0, 0, "", &"", _make_items(), _make_gateways())
	_cache.cache_field(20, 2, 0, 0, "", &"", _make_items(), _make_gateways())
	var ids: Array[int] = _cache.get_cached_lobby_ids()
	assert_eq(ids.size(), 2, "Should have 2 IDs")
	assert_true(10 in ids, "Should contain 10")
	assert_true(20 in ids, "Should contain 20")


# =============================================================================
# Version Tracking
# =============================================================================

func test_first_cache_has_version_1() -> void:
	_cache.cache_field(100, 42, 0, 0, "", &"", _make_items(), _make_gateways())
	assert_eq(_cache.get_state_version(100), 1)


func test_recache_increments_version() -> void:
	_cache.cache_field(100, 42, 0, 0, "", &"", _make_items(), _make_gateways())
	_cache.cache_field(100, 42, 0, 0, "", &"", _make_items(), _make_gateways())
	assert_eq(_cache.get_state_version(100), 2)


func test_get_state_version_returns_0_when_missing() -> void:
	assert_eq(_cache.get_state_version(999), 0)


# =============================================================================
# Merge Logic (Fix 4 verification)
# =============================================================================

func test_merge_entry_accepts_newer_version() -> void:
	# Local: v1
	_cache.cache_field(100, 42, 0, 0, "", &"", _make_items(), _make_gateways())

	# Incoming: v2
	var data: Dictionary = {
		"lobby_id": 100,
		"generation_seed": 42,
		"origin_lobby_id": 0,
		"origin_gateway": 0,
		"origin_map_name": "",
		"pearl_type": "",
		"state_version": 2,
		"last_modified": "",
		"last_modified_by": 5000,
		"items": [],
		"gateways": []
	}
	var result: bool = _cache.merge_entry(data)
	assert_true(result, "Should accept newer version")
	assert_eq(_cache.get_state_version(100), 2)


func test_merge_entry_rejects_older_version() -> void:
	# Local: v1
	_cache.cache_field(100, 42, 0, 0, "", &"", _make_items(), _make_gateways())
	# Recache to bump to v2
	_cache.cache_field(100, 42, 0, 0, "", &"", _make_items(), _make_gateways())

	# Incoming: v1
	var data: Dictionary = {
		"lobby_id": 100,
		"generation_seed": 42,
		"origin_lobby_id": 0,
		"origin_gateway": 0,
		"origin_map_name": "",
		"pearl_type": "",
		"state_version": 1,
		"last_modified": "",
		"last_modified_by": 9999,
		"items": [],
		"gateways": []
	}
	var result: bool = _cache.merge_entry(data)
	assert_false(result, "Should reject older version")
	assert_eq(_cache.get_state_version(100), 2, "Version should remain 2")


func test_merge_entry_tiebreak_higher_steam_id_wins() -> void:
	# Local: v1, modifier 1000
	_cache.cache_field(100, 42, 0, 0, "", &"", _make_items(), _make_gateways(), 1000)

	# Incoming: v1, modifier 9999 (higher, should win)
	var data: Dictionary = {
		"lobby_id": 100,
		"generation_seed": 42,
		"origin_lobby_id": 0,
		"origin_gateway": 0,
		"origin_map_name": "",
		"pearl_type": "",
		"state_version": 1,
		"last_modified": "",
		"last_modified_by": 9999,
		"items": [],
		"gateways": []
	}
	var result: bool = _cache.merge_entry(data)
	assert_true(result, "Higher Steam ID should win tiebreak")


func test_merge_entry_tiebreak_lower_steam_id_loses() -> void:
	# Local: v1, modifier 9999
	_cache.cache_field(100, 42, 0, 0, "", &"", _make_items(), _make_gateways(), 9999)

	# Incoming: v1, modifier 1000 (lower, should lose)
	var data: Dictionary = {
		"lobby_id": 100,
		"generation_seed": 42,
		"origin_lobby_id": 0,
		"origin_gateway": 0,
		"origin_map_name": "",
		"pearl_type": "",
		"state_version": 1,
		"last_modified": "",
		"last_modified_by": 1000,
		"items": [],
		"gateways": []
	}
	var result: bool = _cache.merge_entry(data)
	assert_false(result, "Lower Steam ID should lose tiebreak")


func test_merge_entry_tiebreak_equal_steam_id_keeps_local() -> void:
	# Local: v1, modifier 5000
	_cache.cache_field(100, 42, 0, 0, "", &"", _make_items(), _make_gateways(), 5000)

	# Incoming: v1, modifier 5000 (equal, local wins)
	var data: Dictionary = {
		"lobby_id": 100,
		"generation_seed": 42,
		"origin_lobby_id": 0,
		"origin_gateway": 0,
		"origin_map_name": "",
		"pearl_type": "",
		"state_version": 1,
		"last_modified": "",
		"last_modified_by": 5000,
		"items": [],
		"gateways": []
	}
	var result: bool = _cache.merge_entry(data)
	assert_false(result, "Equal Steam ID should keep local (no replacement)")


func test_merge_entry_new_lobby_always_accepted() -> void:
	# No existing entry for lobby 500
	var data: Dictionary = {
		"lobby_id": 500,
		"generation_seed": 99,
		"origin_lobby_id": 0,
		"origin_gateway": 0,
		"origin_map_name": "TestField",
		"pearl_type": "water_pearl",
		"state_version": 1,
		"last_modified": "",
		"last_modified_by": 1000,
		"items": [{"item_id": "water_pearl", "quantity": 1}],
		"gateways": []
	}
	var result: bool = _cache.merge_entry(data)
	assert_true(result, "New lobby should always be accepted")
	assert_true(_cache.has_cached_state(500))

	var state: FieldStateCache.FieldState = _cache.get_cached_state(500)
	assert_eq(state.generation_seed, 99)
	assert_eq(state.origin_map_name, "TestField")
	assert_eq(state.pearl_type, &"water_pearl")
	assert_eq(state.items.size(), 1)


func test_merge_entries_batch() -> void:
	var entries: Array = [
		{
			"lobby_id": 10,
			"generation_seed": 1,
			"origin_lobby_id": 0,
			"origin_gateway": 0,
			"origin_map_name": "",
			"pearl_type": "",
			"state_version": 1,
			"last_modified": "",
			"last_modified_by": 0,
			"items": [],
			"gateways": []
		},
		{
			"lobby_id": 20,
			"generation_seed": 2,
			"origin_lobby_id": 0,
			"origin_gateway": 0,
			"origin_map_name": "",
			"pearl_type": "",
			"state_version": 1,
			"last_modified": "",
			"last_modified_by": 0,
			"items": [],
			"gateways": []
		}
	]
	_cache.merge_entries(entries)
	assert_true(_cache.has_cached_state(10))
	assert_true(_cache.has_cached_state(20))


# =============================================================================
# Serialization
# =============================================================================

func test_serialize_entry_roundtrip() -> void:
	var items: Array[Dictionary] = _make_items(3)
	var gws: Array[Dictionary] = _make_gateways(2)
	_cache.cache_field(100, 42, 200, 1, "Origin", &"air_pearl", items, gws, 7777)

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
	assert_eq(state.items.size(), 3)
	assert_eq(state.gateways.size(), 2)


func test_serialize_all_includes_all_entries() -> void:
	_cache.cache_field(10, 1, 0, 0, "", &"", _make_items(), _make_gateways())
	_cache.cache_field(20, 2, 0, 0, "", &"", _make_items(), _make_gateways())
	_cache.cache_field(30, 3, 0, 0, "", &"", _make_items(), _make_gateways())
	var entries: Array[Dictionary] = _cache.serialize_all()
	assert_eq(entries.size(), 3)


func test_serialize_entry_returns_empty_for_unknown_lobby() -> void:
	var result: Dictionary = _cache.serialize_entry(999)
	assert_true(result.is_empty(), "Should return empty dict for unknown lobby")


# =============================================================================
# Orphan Cleanup
# =============================================================================

func test_cleanup_orphaned_fields_removes_unlinked() -> void:
	_cache.cache_field(100, 1, 0, 0, "", &"", _make_items(), _make_gateways())
	_cache.cache_field(200, 2, 0, 0, "", &"", _make_items(), _make_gateways())
	_cache.cache_field(300, 3, 0, 0, "", &"", _make_items(), _make_gateways())

	# Only 200 is linked
	var linked: Array[int] = [200]
	_cache.cleanup_orphaned_fields(linked)

	assert_false(_cache.has_cached_state(100), "100 should be removed")
	assert_true(_cache.has_cached_state(200), "200 should survive")
	assert_false(_cache.has_cached_state(300), "300 should be removed")


func test_cleanup_orphaned_fields_preserves_linked() -> void:
	_cache.cache_field(100, 1, 0, 0, "", &"", _make_items(), _make_gateways())
	_cache.cache_field(200, 2, 0, 0, "", &"", _make_items(), _make_gateways())

	var linked: Array[int] = [100, 200]
	_cache.cleanup_orphaned_fields(linked)

	assert_true(_cache.has_cached_state(100))
	assert_true(_cache.has_cached_state(200))
