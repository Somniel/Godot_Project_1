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
	var items: Array[Dictionary] = []  # [{item_id, position, quantity}]
	var gateways: Array[Dictionary] = []  # [{id, linked_lobby_id, linked_map_name, generation_seed}]

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


## Maps old lobby IDs to their cached field states
var _cache: Dictionary = {}  # int (lobby_id) -> FieldState

## Maps old lobby IDs to the new lobby IDs (after re-hosting)
var _lobby_id_remapping: Dictionary = {}  # int (old_id) -> int (new_id)


## Cache a field's state before leaving it
func cache_field(
	lobby_id: int,
	generation_seed: int,
	origin_lobby_id: int,
	origin_gateway: int,
	origin_map_name: String,
	pearl_type: StringName,
	items: Array[Dictionary],
	gateways: Array[Dictionary]
) -> void:
	var state := FieldState.new(generation_seed, origin_lobby_id, origin_gateway, origin_map_name, pearl_type)
	state.items = items.duplicate(true)
	state.gateways = gateways.duplicate(true)
	_cache[lobby_id] = state
	print("FieldStateCache: Cached field state for lobby %d (seed %d, pearl %s, %d items, %d gateways)" % [
		lobby_id, generation_seed, pearl_type, items.size(), gateways.size()
	])


## Check if we have cached state for a given lobby ID
func has_cached_state(lobby_id: int) -> bool:
	# Check direct cache
	if _cache.has(lobby_id):
		return true
	# Check if this was remapped to a new ID
	for old_id: int in _lobby_id_remapping:
		if _lobby_id_remapping[old_id] == lobby_id:
			return _cache.has(old_id)
	return false


## Get cached state for a lobby ID (returns null if not found)
func get_cached_state(lobby_id: int) -> FieldState:
	# Direct lookup
	if _cache.has(lobby_id):
		return _cache[lobby_id]
	# Check remapping (maybe they're using an old ID that was remapped)
	return null


## Get the original lobby ID for a remapped ID
func get_original_lobby_id(new_lobby_id: int) -> int:
	for old_id: int in _lobby_id_remapping:
		if _lobby_id_remapping[old_id] == new_lobby_id:
			return old_id
	return new_lobby_id


## Get the current (possibly remapped) lobby ID for an old lobby ID.
## If the old ID was remapped to a new ID, returns the new ID.
## Otherwise returns the original ID.
func get_current_lobby_id(old_lobby_id: int) -> int:
	if _lobby_id_remapping.has(old_lobby_id):
		return _lobby_id_remapping[old_lobby_id]
	return old_lobby_id


## Register that an old lobby ID has been remapped to a new one (after re-hosting)
func register_lobby_remapping(old_lobby_id: int, new_lobby_id: int) -> void:
	_lobby_id_remapping[old_lobby_id] = new_lobby_id
	print("FieldStateCache: Remapped lobby %d -> %d" % [old_lobby_id, new_lobby_id])


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
	_lobby_id_remapping.clear()
	print("FieldStateCache: Cleared %d cached field states" % count)


## Clean up orphaned fields that are no longer linked to any hosted map.
## linked_lobby_ids: Array of lobby IDs that the current map's gateways link to.
func cleanup_orphaned_fields(linked_lobby_ids: Array[int]) -> void:
	var to_remove: Array[int] = []

	for lobby_id: int in _cache:
		# Check if this cached field is still linked from the current map
		var is_linked: bool = false
		for linked_id: int in linked_lobby_ids:
			if linked_id == lobby_id:
				is_linked = true
				break
			# Also check remapped IDs
			if _lobby_id_remapping.has(lobby_id):
				if _lobby_id_remapping[lobby_id] == linked_id:
					is_linked = true
					break

		if not is_linked:
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
	print("Lobby remappings (%d entries):" % _lobby_id_remapping.size())
	for old_id: int in _lobby_id_remapping:
		print("  - %d -> %d" % [old_id, _lobby_id_remapping[old_id]])
