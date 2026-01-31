class_name FieldTownLinker
extends RefCounted
## Manages bidirectional gateway linking between fields and their origin town.
## All access goes through MapManager's shared TownCloudStorage instance
## to prevent stale overwrites from concurrent readers/writers.
##
## All methods take explicit parameters rather than storing field state.
## References SteamManager, LobbyManager, and MapManager singletons for
## Steam I/O and current lobby information.


func _get_storage() -> TownCloudStorage:
	## Get the shared TownCloudStorage, loading from disk if needed.
	return MapManager.ensure_town_storage_loaded()


static func _parse_linked_lobby_id(gw_dict: Dictionary) -> int:
	## Parse linked_lobby_id from gateway dict, handling string or int storage.
	var linked_id_value: Variant = gw_dict.get("linked_lobby_id", "0")
	if linked_id_value is String:
		@warning_ignore("unsafe_cast")
		return (linked_id_value as String).to_int()
	elif linked_id_value is int or linked_id_value is float:
		# Type-narrowed Variant; int() cast is safe after is-check
		@warning_ignore("unsafe_call_argument")
		return int(linked_id_value)
	return 0


# =============================================================================
# Gateway Linking
# =============================================================================

func update_town_gateway_to_link_here(
	town_gateway_id: int,
	field_gateway_id: int,
	generation_seed: int,
	pearl_type: StringName
) -> void:
	## Update the player's town save to link specified gateway to this field.
	## field_gateway_id specifies which field gateway the town gateway connects to.
	var storage: TownCloudStorage = _get_storage()

	if town_gateway_id < 0 or town_gateway_id >= 4:
		push_warning("FieldTownLinker: Town gateway ID %d out of range" % town_gateway_id)
		return

	var field_name: String = "Field %d" % generation_seed
	storage.set_gateway_config(
		town_gateway_id, generation_seed, field_name, pearl_type, field_gateway_id
	)
	storage.set_gateway_link(
		town_gateway_id, LobbyManager.current_lobby_id, field_name, field_gateway_id
	)
	storage.flush()

	print("FieldTownLinker: Updated town gateway %d -> field gateway %d (lobby %d)" % [
		town_gateway_id, field_gateway_id, LobbyManager.current_lobby_id
	])


func restore_town_gateway_links(
	gateways: Array[Gateway],
	generation_seed: int,
	origin_map_name: String
) -> int:
	## Restore field->town links from town cloud gateway data.
	## Town gateways store which field gateway they connect to via linked_gateway_id.
	## Creates reverse town links on the field side for any stored linked_gateway_id
	## that points to an unconfigured field gateway.
	## Returns the number of links created.
	var storage: TownCloudStorage = _get_storage()

	var current_town_lobby: int = MapManager.get_own_town_lobby_id()
	var owner_steam_id: int = SteamManager.get_steam_id()
	var town_name: String = origin_map_name if not origin_map_name.is_empty() else "Town"
	var links_created: int = 0

	for i: int in range(4):
		var gw_dict: Dictionary = storage.get_gateway(i)

		# Only process gateways that link to this field (by seed)
		var gen_seed: int = gw_dict.get("generation_seed", 0)
		if gen_seed != generation_seed:
			continue

		# Only process if there's an explicit linked_gateway_id stored
		var field_gw_id: int = gw_dict.get("linked_gateway_id", -1)
		if field_gw_id < 0 or field_gw_id >= gateways.size():
			continue

		var field_gateway: Gateway = gateways[field_gw_id]

		# Skip if this field gateway is already configured (origin or has link)
		if field_gateway.is_origin_gateway or field_gateway.has_link():
			continue

		# Create town link on this field gateway back to town gateway i
		field_gateway.set_town_link(owner_steam_id, current_town_lobby, town_name, i)
		links_created += 1
		print("FieldTownLinker: Restored town link: field gateway %d -> town gateway %d" % [
			field_gw_id, i
		])

	if links_created > 0:
		print("FieldTownLinker: Restored %d town gateway links from town cloud" % links_created)

	return links_created


func update_all_town_gateways_for_field(
	gateways: Array[Gateway],
	generation_seed: int,
	origin_map_name: String
) -> void:
	## Update all town gateways that link to this field with the current lobby ID.
	## Also auto-assigns unconfigured field gateways to town gateways that don't
	## have a linked_gateway_id yet, creating bidirectional links.
	## Handles all scenarios:
	## - First creation: origin gateway has seed but linked_lobby_id = 0
	## - Restoration: gateways have old lobby IDs that need updating
	## - Recreation (after game restart): gateways have stale lobby IDs
	var storage: TownCloudStorage = _get_storage()

	var current_lobby_id: int = LobbyManager.current_lobby_id
	var current_town_lobby: int = MapManager.get_own_town_lobby_id()
	var owner_steam_id: int = SteamManager.get_steam_id()
	var town_name: String = origin_map_name if not origin_map_name.is_empty() else "Town"
	var modified: bool = false

	# Check each gateway to see if it links to this field
	for i: int in range(4):
		var gw_dict: Dictionary = storage.get_gateway(i)

		# Check if this gateway has matching generation_seed (links to this field)
		var gen_seed: int = gw_dict.get("generation_seed", 0)
		if gen_seed != generation_seed:
			continue

		var linked_id: int = _parse_linked_lobby_id(gw_dict)

		# Find which field gateway connects to this town gateway
		var field_gateway_id: int = find_field_gateway_for_town_gateway(gateways, i)

		# Get existing linked_gateway_id from town cloud
		var existing_linked_gw: int = gw_dict.get("linked_gateway_id", -1)

		# If no field gateway links to this town gateway, auto-assign one
		if field_gateway_id < 0:
			if existing_linked_gw >= 0 and existing_linked_gw < gateways.size():
				# Town cloud has a stored value - use it if field gateway is available
				var stored_gw: Gateway = gateways[existing_linked_gw]
				if not stored_gw.is_origin_gateway and not stored_gw.has_link():
					stored_gw.set_town_link(
						owner_steam_id, current_town_lobby, town_name, i
					)
					field_gateway_id = existing_linked_gw
					print("FieldTownLinker: Restored auto-link: field gw %d -> town gw %d" % [
						field_gateway_id, i
					])
			if field_gateway_id < 0:
				# No stored value or stored gateway was taken - find any available
				var available_gw: int = find_unconfigured_field_gateway(gateways)
				if available_gw >= 0:
					gateways[available_gw].set_town_link(
						owner_steam_id, current_town_lobby, town_name, i
					)
					field_gateway_id = available_gw
					print("FieldTownLinker: Auto-assigned field gw %d -> town gw %d" % [
						field_gateway_id, i
					])

		# Check if update is needed (lobby ID changed or linked_gateway_id changed)
		var needs_update: bool = (linked_id != current_lobby_id) or \
			(field_gateway_id >= 0 and existing_linked_gw != field_gateway_id)
		if not needs_update:
			continue

		# Update this gateway with the current field lobby ID and linked_gateway_id
		if linked_id == 0:
			print("FieldTownLinker: Setting town gw %d -> field gw %d (lobby %d, first)" % [
				i, field_gateway_id, current_lobby_id
			])
		else:
			print("FieldTownLinker: Updating town gw %d -> field gw %d (lobby %d)" % [
				i, field_gateway_id, current_lobby_id
			])

		# Preserve existing linked_gateway_id if we couldn't find the
		# matching field gateway (avoids corrupting cloud data)
		var effective_gw_id: int = field_gateway_id if field_gateway_id >= 0 \
			else existing_linked_gw
		var map_name: String = gw_dict.get("linked_map_name", "Field %d" % generation_seed)
		storage.set_gateway_link(i, current_lobby_id, map_name, effective_gw_id)
		modified = true

	if modified:
		storage.flush()
		print("FieldTownLinker: Updated town gateways with field lobby ID %d" % current_lobby_id)


func find_field_gateway_for_town_gateway(
	gateways: Array[Gateway],
	town_gateway_id: int
) -> int:
	## Find which field gateway connects to a given town gateway.
	## Returns the field gateway ID, or -1 if not found.
	var my_steam_id: int = SteamManager.get_steam_id()

	for gateway: Gateway in gateways:
		# Check if this field gateway links to our town (by Steam ID)
		if not gateway.is_town_link():
			continue
		if gateway.linked_owner_steam_id != my_steam_id:
			continue

		# Check if this field gateway targets the specific town gateway
		if gateway.linked_gateway_id == town_gateway_id:
			return gateway.gateway_id

	return -1


func find_unconfigured_field_gateway(gateways: Array[Gateway]) -> int:
	## Find the first field gateway that has no link and is not the origin.
	## Returns -1 if all gateways are configured.
	for gateway: Gateway in gateways:
		if not gateway.is_origin_gateway and not gateway.has_link():
			return gateway.gateway_id
	return -1


func clear_town_gateway_link(generation_seed: int) -> void:
	## Clear any town gateway that links to this field.
	## Called when clearing a bidirectional field-to-town link.
	var storage: TownCloudStorage = _get_storage()

	var current_lobby_id: int = LobbyManager.current_lobby_id
	var modified: bool = false

	# Find and clear any gateway that links to this field
	for i: int in range(4):
		var gw_dict: Dictionary = storage.get_gateway(i)
		var linked_id: int = _parse_linked_lobby_id(gw_dict)
		var gen_seed: int = gw_dict.get("generation_seed", 0)

		# Match by lobby ID or by generation seed (for this field)
		if linked_id == current_lobby_id or (gen_seed > 0 and gen_seed == generation_seed):
			print("FieldTownLinker: Clearing town gateway %d that links to this field" % i)
			storage.clear_gateway_link(i)
			modified = true

	if modified:
		storage.flush()
		print("FieldTownLinker: Cleared bidirectional town gateway link")
