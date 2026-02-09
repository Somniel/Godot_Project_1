class_name FieldStateCache
extends RefCounted
## Caches field states using CRDT 2P-Set for conflict-free replication.
## removed_items and placed_items are grow-only sets — data is never lost on merge.
## Fields persist in cache as long as they are directly linked to the currently hosted map.

## Maximum valid position coordinate (matches ProceduralFieldGenerator.FIELD_HALF_SIZE)
const FIELD_HALF_SIZE: float = 18.0
## Maximum valid item quantity for a single world item
const MAX_ITEM_QUANTITY: int = 999


## Cached CRDT state for a single field
class FieldState:
	var generation_seed: int = 0
	var origin_lobby_id: int = 0
	var origin_gateway: int = 0
	var origin_map_name: String = ""
	var pearl_type: StringName = &""
	var last_modified: String = ""  # ISO timestamp
	var last_modified_by: int = 0  # Steam ID of last modifier
	## Grow-only set of removed item instance IDs.
	## Key: String (instance_id), Value: Dictionary (action metadata)
	## Metadata: {field_lobby_id: int, field_host_steam_id: int, timestamp: int}
	var removed_items: Dictionary = {}
	## Grow-only set of player-placed items.
	## Key: String (instance_id), Value: Dictionary (item + metadata)
	## Value: {instance_id: String, item_id: String, position: Dict,
	##   quantity: int, field_lobby_id: int, field_host_steam_id: int,
	##   timestamp: int}
	var placed_items: Dictionary = {}
	## Per-gateway version counters for independent gateway state tracking
	var gateway_versions: Array[int] = [0, 0, 0, 0]
	## Gateway structure:
	## {
	##   id: int,
	##   link_type: String ("none", "field", "town"),
	##   linked_lobby_id: int (cached, may be stale),
	##   linked_map_name: String,
	##   linked_gateway_id: int,
	##   generation_seed: int (for field links),
	##   pearl_type: String (for field links),
	##   linked_owner_steam_id: int (for town links)
	## }
	var gateways: Array[Dictionary] = []

	func _init(
		p_seed: int = 0,
		p_origin_lobby: int = 0,
		p_origin_gateway: int = 0,
		p_origin_name: String = "",
		p_pearl_type: StringName = &""
	) -> void:
		generation_seed = p_seed
		origin_lobby_id = p_origin_lobby
		origin_gateway = p_origin_gateway
		origin_map_name = p_origin_name
		pearl_type = p_pearl_type
		last_modified = ""
		last_modified_by = 0


## Maps lobby IDs to their cached field states
var _cache: Dictionary = {}  # int (lobby_id) -> FieldState

# =============================================================================
# Validation Helpers
# =============================================================================


## Validate that an instance_id matches expected formats:
## "gen_{seed}_{index}" or "placed_{steam_id}_{time}_{counter}"
static func is_valid_instance_id(iid: String) -> bool:
	if iid.begins_with("gen_"):
		var parts: PackedStringArray = iid.split("_")
		return parts.size() == 3 and parts[1].is_valid_int() and parts[2].is_valid_int()
	if iid.begins_with("placed_"):
		var parts: PackedStringArray = iid.split("_")
		return (
			parts.size() == 4
			and parts[1].is_valid_int()
			and parts[2].is_valid_int()
			and parts[3].is_valid_int()
		)
	if iid.begins_with("migrated_"):
		# Legacy migration IDs from snapshot-to-CRDT conversion
		return true
	return false


## Validate a placed_items entry has required fields and sane values
static func is_valid_placed_entry(entry: Dictionary) -> bool:
	if not entry.has("instance_id") or not entry.has("item_id"):
		return false
	if not entry.has("position") or not entry.has("quantity"):
		return false

	var quantity: int = entry.get("quantity", 0)
	if quantity < 1 or quantity > MAX_ITEM_QUANTITY:
		return false

	var pos: Variant = entry.get("position", null)
	if pos is Dictionary:
		@warning_ignore("unsafe_cast")
		var pos_dict: Dictionary = pos as Dictionary
		var x: float = pos_dict.get("x", 0.0)
		var z: float = pos_dict.get("z", 0.0)
		if absf(x) > FIELD_HALF_SIZE or absf(z) > FIELD_HALF_SIZE:
			return false

	return true


# =============================================================================
# Cache Operations
# =============================================================================


## Cache a field's CRDT state before leaving it
func cache_field(
	lobby_id: int,
	generation_seed: int,
	origin_lobby_id: int,
	origin_gateway: int,
	origin_map_name: String,
	pearl_type: StringName,
	removed_items: Dictionary,
	placed_items: Dictionary,
	gateway_versions: Array[int],
	gateways: Array[Dictionary],
	modifier_steam_id: int = 0
) -> void:
	var state := FieldState.new(
		generation_seed, origin_lobby_id, origin_gateway, origin_map_name, pearl_type
	)
	state.removed_items = removed_items.duplicate(true)
	state.placed_items = placed_items.duplicate(true)
	state.gateway_versions = gateway_versions.duplicate()
	state.gateways = gateways.duplicate(true)
	state.last_modified = Time.get_datetime_string_from_system(true)
	state.last_modified_by = modifier_steam_id

	_cache[lobby_id] = state
	print(
		(
			(
				"FieldStateCache: Cached field for lobby %d "
				+ "(seed %d, pearl %s, %d removed, %d placed, %d gateways)"
			)
			% [
				lobby_id,
				generation_seed,
				pearl_type,
				removed_items.size(),
				placed_items.size(),
				gateways.size()
			]
		)
	)


## Check if we have cached state for a given lobby ID
func has_cached_state(lobby_id: int) -> bool:
	return _cache.has(lobby_id)


## Get cached state for a lobby ID (returns null if not found)
func get_cached_state(lobby_id: int) -> FieldState:
	if _cache.has(lobby_id):
		return _cache[lobby_id]
	return null


## Remove cached state for a lobby ID
func remove_cached_state(lobby_id: int) -> void:
	if _cache.has(lobby_id):
		@warning_ignore("return_value_discarded")
		_cache.erase(lobby_id)
		print("FieldStateCache: Removed cached state for lobby %d" % lobby_id)


## Clear all cached field states (called when returning to town)
func clear_all() -> void:
	var count: int = _cache.size()
	_cache.clear()
	print("FieldStateCache: Cleared %d cached field states" % count)


## Clean up orphaned fields that are no longer linked to any hosted map.
## linked_lobby_ids: Array of lobby IDs that the current map's gateways link to.
func cleanup_orphaned_fields(linked_lobby_ids: Array[int]) -> void:
	var to_remove: Array[int] = []

	for lobby_id: int in _cache:
		if lobby_id not in linked_lobby_ids:
			to_remove.append(lobby_id)

	for lobby_id: int in to_remove:
		remove_cached_state(lobby_id)

	if to_remove.size() > 0:
		print("FieldStateCache: Cleaned up %d orphaned fields" % to_remove.size())


## Get all cached lobby IDs
func get_cached_lobby_ids() -> Array[int]:
	var ids: Array[int] = []
	for key: int in _cache:
		ids.append(key)
	return ids


## Debug: print cache contents
func debug_print() -> void:
	print("FieldStateCache contents (%d entries):" % _cache.size())
	for lobby_id: int in _cache:
		var state: FieldState = _cache[lobby_id]
		print(
			(
				"  - Lobby %d: seed=%d, removed=%d, placed=%d, gateways=%d"
				% [
					lobby_id,
					state.generation_seed,
					state.removed_items.size(),
					state.placed_items.size(),
					state.gateways.size()
				]
			)
		)


# =============================================================================
# Serialization for Network Sync
# =============================================================================


## Serialize a single cache entry for network transfer
func serialize_entry(lobby_id: int) -> Dictionary:
	if not _cache.has(lobby_id):
		return {}

	var state: FieldState = _cache[lobby_id]
	return {
		"lobby_id": lobby_id,
		"generation_seed": state.generation_seed,
		"origin_lobby_id": state.origin_lobby_id,
		"origin_gateway": state.origin_gateway,
		"origin_map_name": state.origin_map_name,
		"pearl_type": String(state.pearl_type),
		"last_modified": state.last_modified,
		"last_modified_by": state.last_modified_by,
		"removed_items": state.removed_items.duplicate(true),
		"placed_items": state.placed_items.duplicate(true),
		"gateway_versions": state.gateway_versions.duplicate(),
		"gateways": state.gateways.duplicate(true)
	}


## Serialize all cache entries for network transfer
func serialize_all() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for lobby_id: int in _cache:
		entries.append(serialize_entry(lobby_id))
	return entries


# =============================================================================
# CRDT Merge (Set Union)
# =============================================================================


## Merge a serialized cache entry using CRDT set union.
## removed_items and placed_items are unioned (any key in either set is kept).
## gateway_versions use per-slot max. Always returns true since CRDT merge
## never rejects data — it only grows.
func merge_entry(data: Dictionary) -> bool:
	var lobby_id: int = data.get("lobby_id", 0)
	if lobby_id <= 0:
		return false

	var seed_val: int = data.get("generation_seed", 0)
	var origin_lobby: int = data.get("origin_lobby_id", 0)
	var origin_gw: int = data.get("origin_gateway", 0)
	var origin_name: String = data.get("origin_map_name", "")
	var pearl_str: String = data.get("pearl_type", "")
	var pearl_type: StringName = StringName(pearl_str) if not pearl_str.is_empty() else &""

	# Parse incoming CRDT sets
	var incoming_removed: Dictionary = _parse_dict(data.get("removed_items", {}))
	var incoming_placed: Dictionary = _parse_dict(data.get("placed_items", {}))
	var incoming_gw_versions: Array[int] = _parse_gateway_versions(data.get("gateway_versions", []))
	var incoming_gateways: Array[Dictionary] = _parse_gateways(data.get("gateways", []))

	# Validate incoming data
	incoming_removed = _filter_valid_removed(incoming_removed)
	incoming_placed = _filter_valid_placed(incoming_placed)

	if _cache.has(lobby_id):
		# Union merge with existing state
		var existing: FieldState = _cache[lobby_id]
		_union_dict(existing.removed_items, incoming_removed)
		_union_dict(existing.placed_items, incoming_placed)
		_merge_gateway_versions(existing.gateway_versions, incoming_gw_versions)
		_merge_gateways(existing, incoming_gateways, incoming_gw_versions)
		existing.last_modified = Time.get_datetime_string_from_system(true)
		existing.last_modified_by = data.get("last_modified_by", 0)
		print(
			(
				("FieldStateCache: Merged entry for lobby %d " + "(seed %d, %d removed, %d placed)")
				% [lobby_id, seed_val, existing.removed_items.size(), existing.placed_items.size()]
			)
		)
	else:
		# New entry — accept as-is
		var state := FieldState.new(seed_val, origin_lobby, origin_gw, origin_name, pearl_type)
		state.removed_items = incoming_removed.duplicate(true)
		state.placed_items = incoming_placed.duplicate(true)
		state.gateway_versions = incoming_gw_versions.duplicate()
		state.gateways = incoming_gateways.duplicate(true)
		state.last_modified = data.get("last_modified", "")
		state.last_modified_by = data.get("last_modified_by", 0)
		_cache[lobby_id] = state
		print(
			(
				(
					"FieldStateCache: Added new entry for lobby %d "
					+ "(seed %d, %d removed, %d placed)"
				)
				% [lobby_id, seed_val, state.removed_items.size(), state.placed_items.size()]
			)
		)

	return true


## Merge multiple cache entries from network
func merge_entries(entries: Array) -> void:
	for entry: Variant in entries:
		if entry is Dictionary:
			@warning_ignore("unsafe_cast", "return_value_discarded")
			merge_entry(entry as Dictionary)


# =============================================================================
# Internal Merge Helpers
# =============================================================================


## Union source dictionary into target (target gains all keys from source).
## For matching keys, existing values are preserved (first-write wins for CRDT).
static func _union_dict(target: Dictionary, source: Dictionary) -> void:
	for key: Variant in source:
		if not target.has(key):
			target[key] = source[key]


## Merge gateway_versions arrays: per-slot max
static func _merge_gateway_versions(local: Array[int], incoming: Array[int]) -> void:
	for i: int in range(mini(local.size(), incoming.size())):
		if incoming[i] > local[i]:
			local[i] = incoming[i]


## Merge gateways: for each slot where incoming version is higher, replace
static func _merge_gateways(
	state: FieldState, incoming_gateways: Array[Dictionary], incoming_gw_versions: Array[int]
) -> void:
	for i: int in range(mini(incoming_gateways.size(), 4)):
		if i < incoming_gw_versions.size() and i < state.gateway_versions.size():
			if incoming_gw_versions[i] > state.gateway_versions[i]:
				# Replace gateway at this slot
				while state.gateways.size() <= i:
					state.gateways.append({})
				state.gateways[i] = incoming_gateways[i].duplicate(true)


## Filter removed_items dict to only valid instance IDs
static func _filter_valid_removed(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in data:
		if key is String:
			@warning_ignore("unsafe_cast")
			if is_valid_instance_id(key as String):
				result[key] = data[key]
			else:
				push_warning("FieldStateCache: Rejected invalid removed_items key: %s" % str(key))
	return result


## Filter placed_items dict to only valid entries
static func _filter_valid_placed(data: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key: Variant in data:
		if key is String:
			@warning_ignore("unsafe_cast")
			var key_str: String = key as String
			if not is_valid_instance_id(key_str):
				push_warning("FieldStateCache: Rejected invalid placed_items key: %s" % key_str)
				continue
			var entry: Variant = data[key]
			if entry is Dictionary:
				@warning_ignore("unsafe_cast")
				var entry_dict: Dictionary = entry as Dictionary
				if is_valid_placed_entry(entry_dict):
					result[key] = entry_dict
				else:
					push_warning("FieldStateCache: Rejected invalid placed entry: %s" % key_str)
	return result


## Safely parse a Variant that should be a Dictionary
static func _parse_dict(value: Variant) -> Dictionary:
	if value is Dictionary:
		@warning_ignore("unsafe_cast")
		return (value as Dictionary).duplicate(true)
	return {}


## Parse gateway_versions from Variant (Array or anything)
static func _parse_gateway_versions(value: Variant) -> Array[int]:
	var result: Array[int] = [0, 0, 0, 0]
	if value is Array:
		@warning_ignore("unsafe_cast")
		var arr: Array = value as Array
		for i: int in range(mini(arr.size(), 4)):
			if arr[i] is int:
				result[i] = arr[i]
			elif arr[i] is float:
				@warning_ignore("unsafe_call_argument")
				result[i] = int(arr[i])
	return result


## Parse gateways array from Variant
static func _parse_gateways(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		@warning_ignore("unsafe_cast")
		for gw: Variant in value as Array:
			if gw is Dictionary:
				@warning_ignore("unsafe_cast")
				result.append((gw as Dictionary).duplicate())
	return result
