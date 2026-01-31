class_name FieldCloudPersistence
extends RefCounted
## Handles saving and loading field state to/from the player's town Steam Cloud storage.
## Provides serialization utilities for items and gateways.
##
## The caller (field.gd) is responsible for spawning items and configuring gateways
## from the data returned by load_from_town_cloud().


# =============================================================================
# Position Parsing Utilities
# =============================================================================

static func parse_position(pos_variant: Variant) -> Vector3:
	## Parse position from serialized data (handles Vector3, Dictionary, or String).
	if pos_variant is Vector3:
		@warning_ignore("unsafe_cast")
		return pos_variant as Vector3
	elif pos_variant is Dictionary:
		@warning_ignore("unsafe_cast")
		var pos_dict: Dictionary = pos_variant as Dictionary
		# Dictionary.get() returns Variant; values are provably numeric
		@warning_ignore("unsafe_call_argument")
		return Vector3(
			pos_dict.get("x", 0.0),
			pos_dict.get("y", 0.0),
			pos_dict.get("z", 0.0)
		)
	elif pos_variant is String:
		@warning_ignore("unsafe_cast")
		var pos_str: String = pos_variant as String
		return parse_vector3_string(pos_str)
	return Vector3.ZERO


static func parse_steam_id(value: Variant) -> int:
	## Parse a Steam ID from serialized data (handles String, int, or float).
	## Steam IDs are stored as strings to preserve precision for large 64-bit values.
	if value is String:
		@warning_ignore("unsafe_cast")
		return (value as String).to_int()
	elif value is int or value is float:
		# Type-narrowed Variant; int() cast is safe after is-check
		@warning_ignore("unsafe_call_argument")
		return int(value)
	return 0


static func parse_vector3_string(s: String) -> Vector3:
	## Parse Vector3 from string format "(x, y, z)".
	## Returns Vector3.ZERO if parsing fails.
	var trimmed: String = s.strip_edges()
	if not trimmed.begins_with("(") or not trimmed.ends_with(")"):
		return Vector3.ZERO

	# Remove parentheses and split by comma
	var inner: String = trimmed.substr(1, trimmed.length() - 2)
	var parts: PackedStringArray = inner.split(",")
	if parts.size() != 3:
		return Vector3.ZERO

	var x: float = parts[0].strip_edges().to_float()
	var y: float = parts[1].strip_edges().to_float()
	var z: float = parts[2].strip_edges().to_float()
	return Vector3(x, y, z)


# =============================================================================
# Serialization
# =============================================================================

func serialize_items(item_spawn_target: Node) -> Array[Dictionary]:
	## Serialize all WorldItem children of the given node.
	var items: Array[Dictionary] = []
	if item_spawn_target == null:
		push_warning("FieldCloudPersistence: Null item spawn target")
		return items

	for child: Node in item_spawn_target.get_children():
		if child is WorldItem:
			var item: WorldItem = child as WorldItem
			var pos: Vector3 = item.get_ground_position()
			items.append({
				"item_id": str(item.item_id),
				# Store ground position (without float/bob offset) for proper restoration
				"position": {"x": pos.x, "y": pos.y, "z": pos.z},
				"quantity": item.quantity
			})

	return items


func serialize_gateways(gateways: Array[Gateway]) -> Array[Dictionary]:
	## Serialize all gateway configurations.
	var gateways_data: Array[Dictionary] = []

	for gateway: Gateway in gateways:
		# Convert link_type enum to string
		var link_type_str: String = "none"
		match gateway.link_type:
			Gateway.LinkType.FIELD:
				link_type_str = "field"
			Gateway.LinkType.TOWN:
				link_type_str = "town"

		gateways_data.append({
			"id": gateway.gateway_id,
			"link_type": link_type_str,
			"linked_lobby_id": gateway.linked_lobby_id,
			"linked_map_name": gateway.linked_map_name,
			"generation_seed": gateway.generation_seed,
			"pearl_type": String(gateway.pearl_type),
			"is_origin_gateway": gateway.is_origin_gateway,
			"linked_gateway_id": gateway.linked_gateway_id,
			# Store as string to preserve precision for large Steam IDs
			"linked_owner_steam_id": str(gateway.linked_owner_steam_id)
		})

	return gateways_data


# =============================================================================
# Cloud Save/Load
# =============================================================================

func save_to_town_cloud(
	generation_seed: int,
	pearl_type: StringName,
	items: Array[Dictionary],
	gateways: Array[Dictionary]
) -> bool:
	## Save field state to the player's town Steam Cloud storage.
	## Uses the shared TownCloudStorage instance via MapManager.
	## Returns true on success.
	if generation_seed <= 0:
		return false

	var storage: TownCloudStorage = MapManager.ensure_town_storage_loaded()
	storage.set_linked_field(
		generation_seed, pearl_type, items, gateways,
		0, SteamManager.get_steam_id()
	)
	storage.flush()

	print("FieldCloudPersistence: Saved to town cloud (seed %d, %d items, %d gateways)" % [
		generation_seed, items.size(), gateways.size()
	])
	return true


func load_from_town_cloud(generation_seed: int) -> Variant:
	## Load field state from the player's town Steam Cloud storage.
	## Uses the shared TownCloudStorage instance via MapManager.
	## Returns a Dictionary with "items" and "gateways" arrays, or null if not found.
	if generation_seed <= 0:
		return null

	var storage: TownCloudStorage = MapManager.ensure_town_storage_loaded()
	var field_data: Variant = storage.get_linked_field(generation_seed)

	if field_data == null:
		return null

	print("FieldCloudPersistence: Loaded state for seed %d from town cloud" % generation_seed)
	return field_data
