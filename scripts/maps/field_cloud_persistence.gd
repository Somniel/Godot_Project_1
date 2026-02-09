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
		return Vector3(pos_dict.get("x", 0.0), pos_dict.get("y", 0.0), pos_dict.get("z", 0.0))
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
			items.append(
				{
					"item_id": str(item.item_id),
					"instance_id": item.instance_id,
					"position": {"x": pos.x, "y": pos.y, "z": pos.z},
					"quantity": item.quantity
				}
			)

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

		(
			gateways_data
			. append(
				{
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
				}
			)
		)

	return gateways_data


# =============================================================================
# Cloud Save/Load
# =============================================================================


func save_to_town_cloud(
	generation_seed: int,
	pearl_type: StringName,
	removed_items: Dictionary,
	placed_items: Dictionary,
	gateway_versions: Array[int],
	gateways: Array[Dictionary]
) -> bool:
	## Save field CRDT state to the player's town Steam Cloud storage.
	## Uses the shared TownCloudStorage instance via MapManager.
	## Returns true on success.
	if generation_seed <= 0:
		return false

	var storage: TownCloudStorage = MapManager.ensure_town_storage_loaded()
	storage.set_linked_field(
		generation_seed,
		pearl_type,
		removed_items,
		placed_items,
		gateway_versions,
		gateways,
		SteamManager.get_steam_id()
	)
	storage.flush()

	print(
		(
			(
				"FieldCloudPersistence: Saved CRDT to town cloud "
				+ "(seed %d, %d removed, %d placed, %d gateways)"
			)
			% [generation_seed, removed_items.size(), placed_items.size(), gateways.size()]
		)
	)
	return true


func load_from_town_cloud(generation_seed: int) -> Variant:
	## Load field CRDT state from the player's town Steam Cloud storage.
	## Auto-migrates old snapshot format to CRDT on read.
	## Returns a Dictionary with CRDT fields, or null if not found.
	if generation_seed <= 0:
		return null

	var storage: TownCloudStorage = MapManager.ensure_town_storage_loaded()
	var field_data: Variant = storage.get_linked_field(generation_seed)

	if field_data == null:
		return null

	print("FieldCloudPersistence: Loaded state for seed %d from town cloud" % generation_seed)
	return field_data


# =============================================================================
# Snapshot-to-CRDT Migration
# =============================================================================


static func migrate_snapshot_to_crdt(
	data: Dictionary, generation_seed: int, pearl_type: StringName
) -> Dictionary:
	## Migrate a legacy snapshot-format linked_field entry to CRDT format.
	## Compares saved items against procedurally generated canonical items.
	## Missing items → removed_items, extra items → placed_items.
	var removed_items: Dictionary = {}
	var placed_items: Dictionary = {}
	var gateway_versions: Array[int] = [0, 0, 0, 0]

	# Regenerate canonical items from seed
	var generator := ProceduralFieldGenerator.new(generation_seed, pearl_type)
	var canonical_items: Array[Dictionary] = generator.generate_items()

	# Build a lookup of saved items by rounded position
	var saved_by_pos: Dictionary = {}  # "x,z" -> Array[Dictionary]
	var saved_items_variant: Variant = data.get("items", [])
	if saved_items_variant is Array:
		@warning_ignore("unsafe_cast")
		for item: Variant in saved_items_variant as Array:
			if item is Dictionary:
				@warning_ignore("unsafe_cast")
				var item_dict: Dictionary = item as Dictionary
				var pos: Vector3 = parse_position(item_dict.get("position", Vector3.ZERO))
				var key: String = _round_pos_key(pos)
				if not saved_by_pos.has(key):
					saved_by_pos[key] = []
				# Value is always Array (set on line above); type system can't verify
				@warning_ignore("unsafe_method_access")
				saved_by_pos[key].append(item_dict)

	# Compare canonical items against saved
	for i: int in range(canonical_items.size()):
		var canonical: Dictionary = canonical_items[i]
		var canon_pos: Vector3 = canonical.get("position", Vector3.ZERO)
		var key: String = _round_pos_key(canon_pos)
		var instance_id: String = "gen_%d_%d" % [generation_seed, i]

		var found: bool = false
		if saved_by_pos.has(key):
			var candidates: Array = saved_by_pos[key]
			for j: int in range(candidates.size()):
				var saved: Dictionary = candidates[j]
				if str(saved.get("item_id", "")) == str(canonical.get("item_id", "")):
					found = true
					candidates.remove_at(j)
					if candidates.is_empty():
						@warning_ignore("return_value_discarded")
						saved_by_pos.erase(key)
					break

		if not found:
			# Canonical item not in save → it was removed
			removed_items[instance_id] = {
				"field_lobby_id": 0, "field_host_steam_id": 0, "timestamp": 0
			}

	# Remaining saved items not matched to canonical → they were placed
	var placed_counter: int = 0
	for key: String in saved_by_pos:
		var remaining: Array = saved_by_pos[key]
		for item: Dictionary in remaining:
			var iid: String = "migrated_%d_%d" % [generation_seed, placed_counter]
			placed_counter += 1
			var pos: Vector3 = parse_position(item.get("position", Vector3.ZERO))
			placed_items[iid] = {
				"instance_id": iid,
				"item_id": str(item.get("item_id", "")),
				"position": {"x": pos.x, "y": pos.y, "z": pos.z},
				"quantity": item.get("quantity", 1),
				"field_lobby_id": 0,
				"field_host_steam_id": 0,
				"timestamp": 0
			}

	# Preserve gateways from old format
	var gateways: Array[Dictionary] = []
	var gw_data: Variant = data.get("gateways", [])
	if gw_data is Array:
		@warning_ignore("unsafe_cast")
		for gw: Variant in gw_data as Array:
			if gw is Dictionary:
				@warning_ignore("unsafe_cast")
				gateways.append((gw as Dictionary).duplicate())

	return {
		"format_version": 1,
		"pearl_type": String(pearl_type),
		"removed_items": removed_items,
		"placed_items": placed_items,
		"gateway_versions": gateway_versions,
		"gateways": gateways
	}


static func _round_pos_key(pos: Vector3) -> String:
	## Round position to 2 decimal places for comparison key.
	return "%.2f,%.2f" % [pos.x, pos.z]
