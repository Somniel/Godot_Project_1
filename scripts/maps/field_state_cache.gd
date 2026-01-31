class_name FieldStateCache
extends RefCounted
## Caches field states so they can be restored when returning to a previously visited field.
## Fields persist in cache as long as they are directly linked to the currently hosted map.

## Cached state for a single field
class FieldState:
	var generation_seed: int = 0
	var origin_lobby_id: int = 0
	var origin_gateway: int = 0
	var origin_map_name: String = ""
	var pearl_type: StringName = &""
	## Version tracking for conflict resolution (newest wins)
	var state_version: int = 0  # Incrementing counter
	var last_modified: String = ""  # ISO timestamp
	var last_modified_by: int = 0  # Steam ID of last modifier
	var items: Array[Dictionary] = []  # [{item_id, position, quantity}]
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
		state_version = 0
		last_modified = ""
		last_modified_by = 0


## Maps old lobby IDs to their cached field states
var _cache: Dictionary = {}  # int (lobby_id) -> FieldState


## Cache a field's state before leaving it
func cache_field(
	lobby_id: int,
	generation_seed: int,
	origin_lobby_id: int,
	origin_gateway: int,
	origin_map_name: String,
	pearl_type: StringName,
	items: Array[Dictionary],
	gateways: Array[Dictionary],
	modifier_steam_id: int = 0
) -> void:
	var state := FieldState.new(generation_seed, origin_lobby_id, origin_gateway, origin_map_name, pearl_type)
	state.items = items.duplicate(true)
	state.gateways = gateways.duplicate(true)

	# Handle versioning: increment if updating existing, otherwise start at 1
	# Dictionary.get() returns Variant; safe because _cache only stores FieldState values
	@warning_ignore("unsafe_cast")
	var existing: FieldState = _cache.get(lobby_id, null) as FieldState
	if existing != null:
		state.state_version = existing.state_version + 1
	else:
		state.state_version = 1

	state.last_modified = Time.get_datetime_string_from_system(true)
	state.last_modified_by = modifier_steam_id

	_cache[lobby_id] = state
	print("FieldStateCache: Cached field state for lobby %d (seed %d, pearl %s, %d items, %d gateways, version %d)" % [
		lobby_id, generation_seed, pearl_type, items.size(), gateways.size(), state.state_version
	])


## Check if we have cached state for a given lobby ID
func has_cached_state(lobby_id: int) -> bool:
	return _cache.has(lobby_id)


## Get cached state for a lobby ID (returns null if not found)
func get_cached_state(lobby_id: int) -> FieldState:
	if _cache.has(lobby_id):
		return _cache[lobby_id]
	return null


## Get the state version for a cached field (0 if not found)
func get_state_version(lobby_id: int) -> int:
	if _cache.has(lobby_id):
		var state: FieldState = _cache[lobby_id]
		return state.state_version
	return 0


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
		print("  - Lobby %d: seed=%d, items=%d, gateways=%d" % [
			lobby_id, state.generation_seed, state.items.size(), state.gateways.size()
		])


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
		"state_version": state.state_version,
		"last_modified": state.last_modified,
		"last_modified_by": state.last_modified_by,
		"items": state.items.duplicate(true),
		"gateways": state.gateways.duplicate(true)
	}


## Serialize all cache entries for network transfer
func serialize_all() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for lobby_id: int in _cache:
		entries.append(serialize_entry(lobby_id))
	return entries


## Deserialize and merge a cache entry from network
## Returns true if the entry was merged (newer version), false if skipped
func merge_entry(data: Dictionary) -> bool:
	var lobby_id: int = data.get("lobby_id", 0)
	if lobby_id <= 0:
		return false

	var incoming_version: int = data.get("state_version", 0)

	# Check if we have existing data and compare versions
	if _cache.has(lobby_id):
		var existing: FieldState = _cache[lobby_id]
		if existing.state_version > incoming_version:
			print("FieldStateCache: Skipping merge for lobby %d (local v%d > incoming v%d)" % [
				lobby_id, existing.state_version, incoming_version
			])
			return false
		if existing.state_version == incoming_version:
			# Tiebreaker: higher last_modified_by Steam ID wins
			var incoming_modifier: int = data.get("last_modified_by", 0)
			if existing.last_modified_by >= incoming_modifier:
				print("FieldStateCache: Skipping merge for lobby %d (equal v%d, local modifier wins)" % [
					lobby_id, incoming_version
				])
				return false

	var seed_val: int = data.get("generation_seed", 0)
	var origin_lobby: int = data.get("origin_lobby_id", 0)
	var origin_gw: int = data.get("origin_gateway", 0)
	var origin_name: String = data.get("origin_map_name", "")
	var pearl_str: String = data.get("pearl_type", "")
	var pearl_type: StringName = StringName(pearl_str) if not pearl_str.is_empty() else &""

	var state := FieldState.new(seed_val, origin_lobby, origin_gw, origin_name, pearl_type)

	# Deserialize version info
	state.state_version = incoming_version
	state.last_modified = data.get("last_modified", "")
	state.last_modified_by = data.get("last_modified_by", 0)

	# Deserialize items
	var items_data: Variant = data.get("items", [])
	if items_data is Array:
		@warning_ignore("unsafe_cast")
		for item: Variant in (items_data as Array):
			if item is Dictionary:
				@warning_ignore("unsafe_cast")
				state.items.append((item as Dictionary).duplicate())

	# Deserialize gateways
	var gateways_data: Variant = data.get("gateways", [])
	if gateways_data is Array:
		@warning_ignore("unsafe_cast")
		for gw: Variant in (gateways_data as Array):
			if gw is Dictionary:
				@warning_ignore("unsafe_cast")
				state.gateways.append((gw as Dictionary).duplicate())

	_cache[lobby_id] = state
	print("FieldStateCache: Merged entry for lobby %d (seed %d, v%d, %d items, %d gateways)" % [
		lobby_id, seed_val, state.state_version, state.items.size(), state.gateways.size()
	])
	return true


## Merge multiple cache entries from network
func merge_entries(entries: Array) -> void:
	for entry: Variant in entries:
		if entry is Dictionary:
			@warning_ignore("unsafe_cast", "return_value_discarded")
			merge_entry(entry as Dictionary)
