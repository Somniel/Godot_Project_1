class_name PlayerTownGatewayProvider
extends RefCounted
## Provides read-only access to the player's own town gateway configurations.
## Uses the shared TownCloudStorage instance via MapManager.

signal gateways_loaded(gateways: Array[Dictionary])

const DIRECTION_NAMES: Array[String] = ["North", "East", "South", "West"]


func load_gateways() -> void:
	## Load player's town gateway configurations from the shared storage.
	var gateways: Array[Dictionary] = []

	var storage: TownCloudStorage = MapManager.ensure_town_storage_loaded()
	var town_name: String = storage.get_town_name()

	for i: int in range(4):
		var gw_dict: Dictionary = storage.get_gateway(i)
		var lobby_id: int = FieldTownLinker._parse_linked_lobby_id(gw_dict)
		var gen_seed: int = gw_dict.get("generation_seed", 0)
		var has_link: bool = lobby_id > 0 or gen_seed > 0

		gateways.append(
			{
				"id": gw_dict.get("id", i),
				"has_link": has_link,
				"linked_lobby_id": lobby_id,
				"linked_map_name": gw_dict.get("linked_map_name", ""),
				"generation_seed": gen_seed,
				"pearl_type": gw_dict.get("pearl_type", ""),
				"town_name": town_name
			}
		)

	gateways_loaded.emit(gateways)


static func get_direction_name(gateway_id: int) -> String:
	## Get the direction name for a gateway ID.
	if gateway_id >= 0 and gateway_id < DIRECTION_NAMES.size():
		return DIRECTION_NAMES[gateway_id]
	return "Gateway %d" % gateway_id
