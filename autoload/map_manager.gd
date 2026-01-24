extends Node
## Manages map types, travel coordination, and field lifecycle.
## Tracks whether the current map is a town (persistent) or field (temporary).

## Emitted when a map is loaded
signal map_loaded(map_type: String)

## Emitted when travel to another map starts
signal travel_started(destination_lobby_id: int)

## Emitted when travel completes and new map is loaded
signal travel_completed

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

## Previous town lobby IDs (tracks old IDs when town is re-hosted)
var _previous_town_lobby_ids: Array[int] = []

## Steam ID of the current town's owner (for determining if we can re-host)
var _current_town_owner_id: int = 0

## Cache for field states (allows returning to previously visited fields)
var _field_cache: FieldStateCache = FieldStateCache.new()

## The lobby ID of the field we're currently in (for caching on exit)
var _current_field_lobby_id: int = 0


func _ready() -> void:
	# Connect to network signals for travel coordination
	@warning_ignore("return_value_discarded")
	NetworkManager.host_started.connect(_on_host_started)
	@warning_ignore("return_value_discarded")
	NetworkManager.client_started.connect(_on_client_started)
	@warning_ignore("return_value_discarded")
	NetworkManager.disconnected.connect(_on_disconnected)


func _exit_tree() -> void:
	if NetworkManager.host_started.is_connected(_on_host_started):
		NetworkManager.host_started.disconnect(_on_host_started)
	if NetworkManager.client_started.is_connected(_on_client_started):
		NetworkManager.client_started.disconnect(_on_client_started)
	if NetworkManager.disconnected.is_connected(_on_disconnected):
		NetworkManager.disconnected.disconnect(_on_disconnected)


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


## Check if a given lobby ID is our own town that needs re-hosting.
## Returns true if the lobby_id matches our saved town or belongs to us.
## Used by fields to skip lobby validation for return-to-own-town travel.
func is_own_town_lobby(lobby_id: int) -> bool:
	# Check current town lobby ID
	if lobby_id == _own_town_lobby_id:
		return true
	# Check previous town lobby IDs (from before re-hosting)
	if lobby_id in _previous_town_lobby_ids:
		return true
	# Check if lobby metadata indicates ownership
	return _should_rehost_own_town(lobby_id)


## Check if we have cached state for a field that no longer has an active lobby.
## Used by fields to determine if a destination can be restored.
func has_cached_field(lobby_id: int) -> bool:
	return _field_cache.has_cached_state(lobby_id)


## Cache the current field's state before leaving.
## Called by the field scene when the player is about to travel away.
func cache_current_field(
	items: Array[Dictionary],
	gateways: Array[Dictionary]
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
		lobby_id, gen_seed, origin_lobby, origin_gateway, origin_name, pearl_type, items, gateways
	)


## Restore a cached field by creating a new lobby and loading the saved state.
## Returns true if restoration started, false if no cached state exists.
func restore_cached_field(old_lobby_id: int) -> bool:
	if not _field_cache.has_cached_state(old_lobby_id):
		return false

	var state: FieldStateCache.FieldState = _field_cache.get_cached_state(old_lobby_id)
	if state == null:
		return false

	print("MapManager: Restoring cached field (old lobby %d, seed %d, pearl %s)" % [
		old_lobby_id, state.generation_seed, state.pearl_type
	])

	# Store restoration params
	_pending_field_seed = state.generation_seed
	_pending_field_origin_lobby = state.origin_lobby_id
	_pending_field_origin_gateway = state.origin_gateway
	_pending_field_origin_name = state.origin_map_name
	_pending_field_pearl_type = state.pearl_type
	_creating_field = true
	_restoring_field = true
	_restoring_field_old_lobby_id = old_lobby_id

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


## Clear field restoration state after it's been applied.
func clear_field_restoration() -> void:
	if _restoring_field and _restoring_field_old_lobby_id > 0:
		# Register the lobby ID remapping (old -> new)
		_field_cache.register_lobby_remapping(
			_restoring_field_old_lobby_id,
			LobbyManager.current_lobby_id
		)
		# Remove the cached state since it's now active
		_field_cache.remove_cached_state(_restoring_field_old_lobby_id)

	_restoring_field = false
	_restoring_field_old_lobby_id = 0


## Get the current (possibly remapped) lobby ID for a field.
## Use this when a gateway has a link to a field that may have been restored
## with a new lobby ID.
func get_current_field_lobby_id(old_lobby_id: int) -> int:
	return _field_cache.get_current_lobby_id(old_lobby_id)


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

	# Note: Don't clear field cache here - the town may have gateways linking
	# to cached fields. The cache persists for the session and is only cleared
	# when fields become truly orphaned (no host AND no direct links).

	# Leave current field
	NetworkManager.disconnect_peer()
	LobbyManager.leave_lobby()

	# Check if this is our own town - if so, re-host it
	if lobby_id == _own_town_lobby_id or _should_rehost_own_town(lobby_id):
		_rehost_own_town()
	else:
		# Join someone else's town as client
		LobbyManager.join_lobby(lobby_id)


## Create a new field and travel to it (host only)
func create_field(
	generation_seed: int,
	origin_lobby_id: int,
	origin_gateway: int,
	origin_name: String = "",
	pearl_type: StringName = &""
) -> void:
	print("MapManager: Creating field with seed %d, pearl %s from gateway %d..." % [
		generation_seed, pearl_type, origin_gateway
	])

	# Store field creation params for when lobby is created
	_pending_field_seed = generation_seed
	_pending_field_origin_lobby = origin_lobby_id
	_pending_field_origin_gateway = origin_gateway
	_pending_field_origin_name = origin_name
	_pending_field_pearl_type = pearl_type
	_creating_field = true

	# If we're the town host, save the town lobby ID so we can return
	if is_town_host():
		_own_town_lobby_id = LobbyManager.current_lobby_id
		print("MapManager: Saving town lobby %d for return" % _own_town_lobby_id)

	# Leave current lobby before creating the field lobby
	NetworkManager.disconnect_peer()
	LobbyManager.leave_lobby()

	# Create the field lobby (we'll become host)
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
var _creating_field: bool = false
var _restoring_field: bool = false
var _restoring_field_old_lobby_id: int = 0


# =============================================================================
# Signal Handlers
# =============================================================================

func _on_host_started() -> void:
	# Determine map type from pending state or lobby metadata
	if _creating_field:
		_current_map_type = MAP_TYPE_FIELD
		_setup_field_metadata()
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

	# Track old town lobby ID for origin gateway matching
	if _own_town_lobby_id > 0 and _own_town_lobby_id != LobbyManager.current_lobby_id:
		if _own_town_lobby_id not in _previous_town_lobby_ids:
			_previous_town_lobby_ids.append(_own_town_lobby_id)

	_own_town_lobby_id = LobbyManager.current_lobby_id
	_current_town_owner_id = SteamManager.get_steam_id()
	_current_field_lobby_id = 0  # Not in a field


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

	# Track current field lobby for caching on exit
	_current_field_lobby_id = LobbyManager.current_lobby_id


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
