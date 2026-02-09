extends Node
## Manages map types, travel coordination, and field lifecycle.
## Tracks whether the current map is a town (persistent) or field (temporary).

## Emitted when a map is loaded
signal map_loaded(map_type: String)

## Emitted when travel to another map starts
signal travel_started(destination_lobby_id: int)

## Emitted when travel completes and new map is loaded
signal travel_completed

## Emitted when a staged field lobby is created and ready to be reported
signal staged_field_ready(lobby_id: int)

## Emitted when town state is saved to Steam Cloud (reserved for future use)
@warning_ignore("unused_signal")
signal town_state_saved

## Emitted when town state is loaded from Steam Cloud (reserved for future use)
@warning_ignore("unused_signal")
signal town_state_loaded

## Map type constants
const MAP_TYPE_NONE: String = ""
const MAP_TYPE_TOWN: String = "town"
const MAP_TYPE_FIELD: String = "field"

## Scene paths
const TOWN_SCENE_PATH: String = "res://scenes/maps/town/town.tscn"
const FIELD_SCENE_PATH: String = "res://scenes/maps/field/field.tscn"
const MAIN_MENU_PATH: String = "res://scenes/main_menu/main_menu.tscn"

## Current map type ("town", "field", or "")
var _current_map_type: String = MAP_TYPE_NONE

## Whether we are the host of the current town
var _is_town_host: bool = false

## The lobby ID of our own town (if we have one hosted or are away from it)
var _own_town_lobby_id: int = 0

## Steam ID of the current town's owner (for determining if we can re-host)
var _current_town_owner_id: int = 0

## Cache for field states (allows returning to previously visited fields)
var _field_cache: FieldStateCache = FieldStateCache.new()

## Shared TownCloudStorage instance (singleton across all map scenes).
## All code accesses town cloud state through this instance to prevent
## stale overwrites from multiple independent readers/writers.
var _town_storage: TownCloudStorage = null
var _town_storage_loaded: bool = false

## The lobby ID of the field we're currently in (for caching on exit)
var _current_field_lobby_id: int = 0

## The lobby ID of the map we traveled FROM (used to determine arrival gateway)
var _source_lobby_id: int = 0

## The gateway ID used to leave the source map (-1 if not via gateway)
var _source_gateway_id: int = -1

## The specific gateway ID to arrive at in the destination (-1 = use default logic)
## Set when traveling through a gateway with an explicit target (e.g., town link)
var _target_gateway_id: int = -1

## The link type of the gateway used for travel ("field" or "town")
var _travel_link_type: String = ""

## The owner Steam ID for town link travel (used with travel_to_player_town)
var _travel_owner_steam_id: int = 0


func _ready() -> void:
	# Connect to network signals for travel coordination
	@warning_ignore("return_value_discarded")
	NetworkManager.host_started.connect(_on_host_started)
	@warning_ignore("return_value_discarded")
	NetworkManager.client_started.connect(_on_client_started)
	@warning_ignore("return_value_discarded")
	NetworkManager.disconnected.connect(_on_disconnected)

	# Connect staged lobby signals for two-phase field creation
	@warning_ignore("return_value_discarded")
	LobbyManager.staged_lobby_created.connect(_on_staged_lobby_created)
	@warning_ignore("return_value_discarded")
	LobbyManager.staged_lobby_failed.connect(_on_staged_lobby_failed)

	# Clear travel flag on connection failure
	@warning_ignore("return_value_discarded")
	NetworkManager.connection_failed.connect(_on_connection_failed)
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_join_failed.connect(_on_lobby_join_failed)


func _exit_tree() -> void:
	# Flush any pending town storage saves before shutdown
	if _town_storage != null:
		_town_storage.flush()

	if NetworkManager.host_started.is_connected(_on_host_started):
		NetworkManager.host_started.disconnect(_on_host_started)
	if NetworkManager.client_started.is_connected(_on_client_started):
		NetworkManager.client_started.disconnect(_on_client_started)
	if NetworkManager.disconnected.is_connected(_on_disconnected):
		NetworkManager.disconnected.disconnect(_on_disconnected)
	if LobbyManager.staged_lobby_created.is_connected(_on_staged_lobby_created):
		LobbyManager.staged_lobby_created.disconnect(_on_staged_lobby_created)
	if LobbyManager.staged_lobby_failed.is_connected(_on_staged_lobby_failed):
		LobbyManager.staged_lobby_failed.disconnect(_on_staged_lobby_failed)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
	if LobbyManager.lobby_join_failed.is_connected(_on_lobby_join_failed):
		LobbyManager.lobby_join_failed.disconnect(_on_lobby_join_failed)


# =============================================================================
# Public API
# =============================================================================


## Get the current map type ("town", "field", or "")
func get_current_map_type() -> String:
	return _current_map_type


## Check if we are hosting our own town
func is_town_host() -> bool:
	return _is_town_host and _current_map_type == MAP_TYPE_TOWN


## Check if we own the current town (even if not hosting)
func is_own_town() -> bool:
	return _current_town_owner_id == SteamManager.get_steam_id()


## Get the current lobby ID of our own town.
## Returns 0 if we don't have a town lobby.
func get_own_town_lobby_id() -> int:
	return _own_town_lobby_id


## Check if a given lobby ID is our own town.
## Returns true if the lobby_id matches our current town lobby.
func is_own_town_lobby(lobby_id: int) -> bool:
	if lobby_id <= 0:
		return false
	return lobby_id == _own_town_lobby_id


## Check if we have cached state for a field that no longer has an active lobby.
## Used by fields to determine if a destination can be restored.
func has_cached_field(lobby_id: int) -> bool:
	return _field_cache.has_cached_state(lobby_id)


## Get the field state cache for sync operations.
func get_field_cache() -> FieldStateCache:
	return _field_cache


## Get the shared TownCloudStorage instance, creating it if needed.
## The instance is lazy-initialized and lives for the duration of the session.
func get_town_storage() -> TownCloudStorage:
	if _town_storage == null:
		_town_storage = TownCloudStorage.new()
		_town_storage.setup(self)
	return _town_storage


## Get the shared TownCloudStorage, loading state from disk if not yet loaded.
## Safe to call anywhere - load_state() is synchronous.
func ensure_town_storage_loaded() -> TownCloudStorage:
	var storage: TownCloudStorage = get_town_storage()
	if not _town_storage_loaded:
		storage.load_state()
		_town_storage_loaded = true
	return storage


## Check if town storage has been loaded from disk.
func is_town_storage_loaded() -> bool:
	return _town_storage_loaded


## Get the lobby ID of the map we traveled from (-1 if not via travel)
func get_source_lobby_id() -> int:
	return _source_lobby_id


## Get the gateway ID used to leave the source map (-1 if not via gateway)
func get_source_gateway_id() -> int:
	return _source_gateway_id


## Get the specific gateway ID to arrive at (-1 = use default logic)
func get_target_gateway_id() -> int:
	return _target_gateway_id


## Set the source gateway before traveling (called by map scenes)
## target_gateway_id: specific gateway to arrive at, or -1 for default logic
## link_type: "field" or "town" - the type of link used for travel
## owner_steam_id: Steam ID of the town owner (for town links)
func set_travel_source(
	lobby_id: int,
	gateway_id: int,
	target_gateway_id: int = -1,
	link_type: String = "",
	owner_steam_id: int = 0
) -> void:
	_source_lobby_id = lobby_id
	_source_gateway_id = gateway_id
	_target_gateway_id = target_gateway_id
	_travel_link_type = link_type
	_travel_owner_steam_id = owner_steam_id


## Clear travel source info (called after spawn is complete)
func clear_travel_source() -> void:
	_source_lobby_id = 0
	_source_gateway_id = -1
	_target_gateway_id = -1
	_travel_link_type = ""
	_travel_owner_steam_id = 0


## Get the link type used for travel ("field", "town", or "")
func get_travel_link_type() -> String:
	return _travel_link_type


## Get the owner Steam ID for town link travel (0 if not a town link)
func get_travel_owner_steam_id() -> int:
	return _travel_owner_steam_id


## Cache the current field's CRDT state before leaving.
## Called by the field scene when the player is about to travel away.
func cache_current_field(
	removed_items: Dictionary,
	placed_items: Dictionary,
	gateway_versions: Array[int],
	gateways: Array[Dictionary],
	modifier_steam_id: int = 0
) -> void:
	if _current_map_type != MAP_TYPE_FIELD:
		return
	if _current_field_lobby_id <= 0:
		return

	# Get field metadata from current lobby
	var lobby_id: int = _current_field_lobby_id
	var seed_str: String = LobbyManager.get_lobby_metadata(lobby_id, "generation_seed")
	var origin_str: String = LobbyManager.get_lobby_metadata(lobby_id, "origin_lobby_id")
	var gateway_str: String = LobbyManager.get_lobby_metadata(lobby_id, "origin_gateway")
	var origin_name: String = LobbyManager.get_lobby_metadata(lobby_id, "origin_map_name")
	var pearl_str: String = LobbyManager.get_lobby_metadata(lobby_id, "pearl_type")

	var gen_seed: int = seed_str.to_int() if not seed_str.is_empty() else 0
	var origin_lobby: int = origin_str.to_int() if not origin_str.is_empty() else 0
	var origin_gateway: int = gateway_str.to_int() if not gateway_str.is_empty() else 0
	var pearl_type: StringName = StringName(pearl_str) if not pearl_str.is_empty() else &""

	_field_cache.cache_field(
		lobby_id,
		gen_seed,
		origin_lobby,
		origin_gateway,
		origin_name,
		pearl_type,
		removed_items,
		placed_items,
		gateway_versions,
		gateways,
		modifier_steam_id
	)


## Restore a cached field by creating a new lobby and loading the saved state.
## Returns true if restoration started, false if no cached state exists.
func restore_cached_field(old_lobby_id: int) -> bool:
	if not _field_cache.has_cached_state(old_lobby_id):
		return false

	var state: FieldStateCache.FieldState = _field_cache.get_cached_state(old_lobby_id)
	if state == null:
		return false

	print(
		(
			"MapManager: Restoring cached field (old lobby %d, seed %d, pearl %s)"
			% [old_lobby_id, state.generation_seed, state.pearl_type]
		)
	)

	# Store restoration params
	_pending_field_seed = state.generation_seed
	_pending_field_origin_lobby = state.origin_lobby_id
	_pending_field_origin_gateway = state.origin_gateway
	_pending_field_origin_name = state.origin_map_name
	_pending_field_pearl_type = state.pearl_type
	_creating_field = true
	_restoring_field = true
	_restoring_field_old_lobby_id = old_lobby_id

	# Mark intentional travel so scenes don't treat disconnect as a drop
	is_traveling = true

	# Leave current lobby and create a new one for the restored field
	NetworkManager.disconnect_peer()
	LobbyManager.leave_lobby()
	LobbyManager.create_lobby(8)

	return true


## Get cached field state for restoration (called by field scene on load).
## Returns null if not restoring a cached field.
func get_pending_field_restoration() -> FieldStateCache.FieldState:
	if not _restoring_field:
		return null
	return _field_cache.get_cached_state(_restoring_field_old_lobby_id)


## Store CRDT state to be consumed by the next field creation.
## Used when a client receives travel approval from the town host.
func set_pending_field_crdt(state: Dictionary) -> void:
	_pending_field_crdt = state.duplicate(true)


## Consume the pending CRDT state. Returns empty dict if none stored.
func consume_pending_field_crdt() -> Dictionary:
	var state: Dictionary = _pending_field_crdt
	_pending_field_crdt = {}
	return state


## Clear field restoration state after it's been applied.
func clear_field_restoration() -> void:
	if _restoring_field and _restoring_field_old_lobby_id > 0:
		# Remove the cached state since it's now active
		_field_cache.remove_cached_state(_restoring_field_old_lobby_id)

	_restoring_field = false
	_restoring_field_old_lobby_id = 0


## Host our town from the main menu
func host_town() -> void:
	print("MapManager: Hosting town...")
	_is_town_host = true
	_own_town_lobby_id = 0  # Will be set after lobby creation
	_current_town_owner_id = SteamManager.get_steam_id()

	# Create lobby with town metadata
	LobbyManager.create_lobby(8)  # Max 8 players

	# The lobby_created signal will trigger metadata setup
	# and NetworkManager will auto-start hosting


## Travel to a field map
func travel_to_field(lobby_id: int) -> void:
	if lobby_id <= 0:
		push_warning("MapManager: Invalid field lobby ID")
		return

	print("MapManager: Traveling to field %d..." % lobby_id)
	travel_started.emit(lobby_id)

	# If we're the town host, our town becomes unjoinable
	if is_town_host():
		_own_town_lobby_id = LobbyManager.current_lobby_id
		print("MapManager: Town %d will be unjoinable while away" % _own_town_lobby_id)

	# Mark intentional travel so scenes don't treat disconnect as a drop
	is_traveling = true

	# Leave current lobby and join the field
	NetworkManager.disconnect_peer()
	LobbyManager.leave_lobby()
	LobbyManager.join_lobby(lobby_id)


## Travel back to a town (either our own or someone else's)
func travel_to_town(lobby_id: int) -> void:
	if lobby_id <= 0:
		push_warning("MapManager: Invalid town lobby ID")
		return

	print("MapManager: Traveling to town %d..." % lobby_id)
	travel_started.emit(lobby_id)

	# Mark intentional travel so scenes don't treat disconnect as a drop
	is_traveling = true

	# Leave current field
	NetworkManager.disconnect_peer()
	LobbyManager.leave_lobby()

	# Check if this is our own town - if so, re-host it
	if lobby_id == _own_town_lobby_id or _should_rehost_own_town(lobby_id):
		_rehost_own_town()
	else:
		# Join someone else's town as client
		LobbyManager.join_lobby(lobby_id)


## Travel to a player's town using their Steam ID as a stable identifier.
## If it's our own town, re-hosts it. Otherwise, attempts to find and join
## their lobby.
func travel_to_player_town(owner_steam_id: int) -> void:
	if owner_steam_id <= 0:
		push_warning("MapManager: Invalid owner Steam ID")
		return

	print("MapManager: Traveling to player %d's town..." % owner_steam_id)

	# Mark intentional travel so scenes don't treat disconnect as a drop
	is_traveling = true

	# Disconnect from current map
	NetworkManager.disconnect_peer()
	LobbyManager.leave_lobby()

	if owner_steam_id == SteamManager.get_steam_id():
		# Our own town - re-host it
		travel_started.emit(_own_town_lobby_id)
		_rehost_own_town()
	else:
		# Other player's town - find their lobby
		travel_started.emit(0)
		LobbyManager.find_lobby_by_owner(owner_steam_id, _on_town_lobby_found)


## Create a new field and travel to it (host only)
func create_field(
	generation_seed: int,
	origin_lobby_id: int,
	origin_gateway: int,
	origin_name: String = "",
	pearl_type: StringName = &"",
	origin_owner_steam_id: int = 0
) -> void:
	print(
		(
			"MapManager: Creating field with seed %d, pearl %s " % [generation_seed, pearl_type]
			+ "from gateway %d..." % origin_gateway
		)
	)

	# Store field creation params for when lobby is created
	_pending_field_seed = generation_seed
	_pending_field_origin_lobby = origin_lobby_id
	_pending_field_origin_gateway = origin_gateway
	_pending_field_origin_name = origin_name
	_pending_field_pearl_type = pearl_type
	_pending_field_origin_owner = origin_owner_steam_id
	_creating_field = true

	# If we're the town host, save the town lobby ID so we can return
	if is_town_host():
		_own_town_lobby_id = LobbyManager.current_lobby_id
		print("MapManager: Saving town lobby %d for return" % _own_town_lobby_id)

	if LobbyManager.current_lobby_id != 0:
		# Staged path: create invisible lobby while still connected
		# to the current lobby. The lobby will be promoted after
		# reporting back to the server via RPC.
		print("MapManager: Using staged lobby creation")
		LobbyManager.create_staged_lobby(8)
	else:
		# Direct path: not in a lobby (e.g., fallback)
		LobbyManager.create_lobby(8)


## Re-host our own town (called when returning from a field)
func rehost_own_town() -> void:
	if _own_town_lobby_id <= 0 and not _is_town_host:
		push_warning("MapManager: No town to re-host")
		return

	print("MapManager: Re-hosting own town...")
	_rehost_own_town()


# =============================================================================
# Internal State
# =============================================================================

var _pending_field_seed: int = 0
var _pending_field_origin_lobby: int = 0
var _pending_field_origin_gateway: int = 0
var _pending_field_origin_name: String = ""
var _pending_field_pearl_type: StringName = &""
var _pending_field_origin_owner: int = 0
var _creating_field: bool = false
var _restoring_field: bool = false
var _restoring_field_old_lobby_id: int = 0

## Temporary CRDT state for the next field creation (client travel approval).
## Consumed by the field scene during initialization.
var _pending_field_crdt: Dictionary = {}

## Whether staged field metadata has already been set (skip in _on_host_started)
var _staged_metadata_done: bool = false

## True while an intentional travel is in progress.
## Scenes check this to avoid treating the disconnect as a server drop.
var is_traveling: bool = false

# =============================================================================
# Signal Handlers
# =============================================================================


func _on_host_started() -> void:
	is_traveling = false

	# Determine map type from pending state or lobby metadata
	if _creating_field:
		_current_map_type = MAP_TYPE_FIELD
		if not _staged_metadata_done:
			_setup_field_metadata()
		_staged_metadata_done = false
		_creating_field = false
	else:
		_current_map_type = MAP_TYPE_TOWN
		_setup_town_metadata()

	print("MapManager: Host started, map type: %s" % _current_map_type)
	map_loaded.emit(_current_map_type)

	# Transition to the appropriate scene
	_change_to_current_scene()
	travel_completed.emit()


func _on_client_started() -> void:
	is_traveling = false

	# Read map type from lobby metadata
	var server_type: String = LobbyManager.get_lobby_metadata(
		LobbyManager.current_lobby_id, "server_type"
	)

	if server_type == MAP_TYPE_FIELD:
		_current_map_type = MAP_TYPE_FIELD
	else:
		_current_map_type = MAP_TYPE_TOWN

	# Get town owner for determining re-host eligibility
	var owner_id_str: String = LobbyManager.get_lobby_metadata(
		LobbyManager.current_lobby_id, "owner_steam_id"
	)
	if not owner_id_str.is_empty():
		_current_town_owner_id = owner_id_str.to_int()

	print("MapManager: Client joined %s map" % _current_map_type)
	map_loaded.emit(_current_map_type)

	# Transition to the appropriate scene
	_change_to_current_scene()
	travel_completed.emit()


func _on_disconnected() -> void:
	print("MapManager: Disconnected from map")
	_current_map_type = MAP_TYPE_NONE


func _on_staged_lobby_created(lobby_id: int) -> void:
	## Handle staged lobby creation for two-phase field creation.
	## Sets metadata on the staged lobby and signals readiness.
	if not _creating_field:
		return

	print("MapManager: Staged field lobby %d created, setting metadata" % lobby_id)
	_setup_staged_field_metadata(lobby_id)
	_staged_metadata_done = true
	staged_field_ready.emit(lobby_id)


func _on_staged_lobby_failed(reason: String) -> void:
	## Handle staged lobby creation failure.
	if _creating_field:
		_creating_field = false
		_staged_metadata_done = false
		push_warning("MapManager: Staged field creation failed: %s" % reason)


func finish_staged_field_transition() -> void:
	## Disconnect from the current lobby and promote the staged field lobby.
	## Called by the map scene (town.gd) after reporting the lobby ID back
	## to the server (client path) or updating the gateway (host path).
	print("MapManager: Finishing staged field transition")
	is_traveling = true
	NetworkManager.disconnect_peer()
	# Leave current lobby but preserve the staged lobby for promotion
	LobbyManager.leave_lobby(true)
	LobbyManager.promote_staged_lobby()
	# promote emits lobby_created -> NetworkManager.start_host() ->
	# host_started -> _on_host_started -> scene change


# =============================================================================
# Metadata Setup
# =============================================================================


func _setup_town_metadata() -> void:
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("server_type", MAP_TYPE_TOWN)
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("server_name", "%s's Town" % SteamManager.get_steam_username())
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("owner_steam_id", str(SteamManager.get_steam_id()))

	_own_town_lobby_id = LobbyManager.current_lobby_id
	_current_town_owner_id = SteamManager.get_steam_id()
	_current_field_lobby_id = 0  # Not in a field


## Update lobby metadata with linked field seeds for cross-town discovery.
## Called after town storage loads and gateway links are restored.
func update_town_linked_seeds(town_storage: TownCloudStorage) -> void:
	if town_storage == null:
		return
	var seeds: PackedStringArray = PackedStringArray()
	for i: int in range(4):
		var gw: Dictionary = town_storage.get_gateway(i)
		var seed_val: int = gw.get("generation_seed", 0)
		if seed_val > 0:
			@warning_ignore("return_value_discarded")
			seeds.append(str(seed_val))
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("linked_seeds", ",".join(seeds))
	if not seeds.is_empty():
		print("MapManager: Advertised linked seeds: %s" % ",".join(seeds))


func _setup_field_metadata() -> void:
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("server_type", MAP_TYPE_FIELD)
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("server_name", "Field %d" % _pending_field_seed)
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("origin_lobby_id", str(_pending_field_origin_lobby))
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("origin_gateway", str(_pending_field_origin_gateway))
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("generation_seed", str(_pending_field_seed))
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("origin_map_name", _pending_field_origin_name)
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("pearl_type", str(_pending_field_pearl_type))

	# Store origin owner Steam ID so field can determine ownership without lobby lookup
	var origin_owner: int = _pending_field_origin_owner
	if origin_owner <= 0:
		origin_owner = SteamManager.get_steam_id()
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("origin_owner_steam_id", str(origin_owner))

	# Track current field lobby for caching on exit
	_current_field_lobby_id = LobbyManager.current_lobby_id


func _setup_staged_field_metadata(lobby_id: int) -> void:
	## Set field metadata on a staged (invisible) lobby.
	## Mirrors _setup_field_metadata but uses set_staged_lobby_metadata
	## since the staged lobby is not the current active lobby.
	@warning_ignore("return_value_discarded")
	LobbyManager.set_staged_lobby_metadata("server_type", MAP_TYPE_FIELD)
	@warning_ignore("return_value_discarded")
	LobbyManager.set_staged_lobby_metadata("server_name", "Field %d" % _pending_field_seed)
	@warning_ignore("return_value_discarded")
	LobbyManager.set_staged_lobby_metadata("origin_lobby_id", str(_pending_field_origin_lobby))
	@warning_ignore("return_value_discarded")
	LobbyManager.set_staged_lobby_metadata("origin_gateway", str(_pending_field_origin_gateway))
	@warning_ignore("return_value_discarded")
	LobbyManager.set_staged_lobby_metadata("generation_seed", str(_pending_field_seed))
	@warning_ignore("return_value_discarded")
	LobbyManager.set_staged_lobby_metadata("origin_map_name", _pending_field_origin_name)
	@warning_ignore("return_value_discarded")
	LobbyManager.set_staged_lobby_metadata("pearl_type", str(_pending_field_pearl_type))

	# Store origin owner Steam ID so field can determine ownership
	var origin_owner: int = _pending_field_origin_owner
	if origin_owner <= 0:
		origin_owner = SteamManager.get_steam_id()
	@warning_ignore("return_value_discarded")
	LobbyManager.set_staged_lobby_metadata("origin_owner_steam_id", str(origin_owner))

	# Track current field lobby for caching on exit
	_current_field_lobby_id = lobby_id


func _rehost_own_town() -> void:
	_is_town_host = true
	_current_town_owner_id = SteamManager.get_steam_id()

	# Create a new lobby for our town
	LobbyManager.create_lobby(8)

	# The host_started signal will handle the rest


func _should_rehost_own_town(lobby_id: int) -> bool:
	# Check if this lobby belongs to us by reading metadata
	var owner_id_str: String = LobbyManager.get_lobby_metadata(lobby_id, "owner_steam_id")
	if owner_id_str.is_empty():
		return false
	return owner_id_str.to_int() == SteamManager.get_steam_id()


## Get the appropriate scene path for the current map type
func get_current_scene_path() -> String:
	match _current_map_type:
		MAP_TYPE_TOWN:
			return TOWN_SCENE_PATH
		MAP_TYPE_FIELD:
			return FIELD_SCENE_PATH
		_:
			return MAIN_MENU_PATH


## Change to the scene for the current map type
func _change_to_current_scene() -> void:
	var scene_path: String = get_current_scene_path()
	var current_scene: Node = get_tree().current_scene

	# Don't reload if we're already in the correct scene
	# Exception: Fields always reload since each field has unique procedural generation
	if current_scene != null:
		var current_path: String = current_scene.scene_file_path
		if current_path == scene_path and _current_map_type != MAP_TYPE_FIELD:
			print("MapManager: Already in correct scene: %s" % scene_path)
			return

	print("MapManager: Changing to scene: %s" % scene_path)
	@warning_ignore("return_value_discarded")
	get_tree().change_scene_to_file(scene_path)


func _on_connection_failed(_reason: String) -> void:
	if is_traveling:
		is_traveling = false
		push_warning("MapManager: Travel failed (connection error)")
		@warning_ignore("return_value_discarded")
		get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _on_lobby_join_failed(_reason: String) -> void:
	if is_traveling:
		is_traveling = false
		push_warning("MapManager: Travel failed (lobby join error)")
		@warning_ignore("return_value_discarded")
		get_tree().change_scene_to_file(MAIN_MENU_PATH)


func _on_town_lobby_found(lobby_id: int) -> void:
	## Callback from find_lobby_by_owner when searching for another player's town.
	if lobby_id > 0:
		print("MapManager: Found town lobby %d, joining..." % lobby_id)
		LobbyManager.join_lobby(lobby_id)
	else:
		print("MapManager: Town not currently hosted")
		is_traveling = false
		# Return to main menu since we already disconnected
		@warning_ignore("return_value_discarded")
		get_tree().change_scene_to_file(MAIN_MENU_PATH)
