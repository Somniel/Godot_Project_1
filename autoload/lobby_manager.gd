extends Node
## Manages Steam lobby creation, joining, leaving, and queries.
## Handles lobby metadata for server type and portal linking.

signal lobby_created(lobby_id: int)
signal lobby_create_failed(reason: String)
signal lobby_joined(lobby_id: int)
signal lobby_join_failed(reason: String)
signal lobby_left
signal lobby_list_received(lobbies: Array)
signal lobby_data_received(lobby_id: int, success: bool)

## Lobby type constants from Steam API
const LOBBY_TYPE_PRIVATE: int = 0
const LOBBY_TYPE_FRIENDS_ONLY: int = 1
const LOBBY_TYPE_PUBLIC: int = 2
const LOBBY_TYPE_INVISIBLE: int = 3

## Lobby comparison constants for filters
const LOBBY_COMPARISON_EQUAL: int = 0

## Lobby distance filter constants
const LOBBY_DISTANCE_WORLDWIDE: int = 3

var current_lobby_id: int = 0
var is_host: bool = false
var _steam: Object = null
var _pending_lobby_data_requests: Array[int] = []
var _find_lobby_callback: Callable = Callable()
var _find_lobby_steam_id: int = 0
var _is_finding_lobby: bool = false
var _find_field_callback: Callable = Callable()
var _find_field_seed: int = 0
var _is_finding_field: bool = false


func _ready() -> void:
	@warning_ignore("return_value_discarded")
	SteamManager.steam_initialized.connect(_on_steam_initialized)
	if SteamManager.is_steam_initialized:
		_on_steam_initialized()


func _on_steam_initialized() -> void:
	_steam = SteamManager.get_steam()
	if _steam == null:
		return

	# Connect to Steam lobby callbacks
	# GDExtension singletons require dynamic dispatch - suppress expected warnings
	@warning_ignore("unsafe_property_access", "unsafe_method_access", "return_value_discarded")
	_steam.lobby_created.connect(_on_lobby_created)
	@warning_ignore("unsafe_property_access", "unsafe_method_access", "return_value_discarded")
	_steam.lobby_joined.connect(_on_lobby_joined)
	@warning_ignore("unsafe_property_access", "unsafe_method_access", "return_value_discarded")
	_steam.lobby_match_list.connect(_on_lobby_match_list)
	@warning_ignore("unsafe_property_access", "unsafe_method_access", "return_value_discarded")
	_steam.lobby_data_update.connect(_on_lobby_data_update)


func create_lobby(max_players: int = 8) -> void:
	if _steam == null:
		lobby_create_failed.emit("Steam not initialized")
		return

	if current_lobby_id != 0:
		lobby_create_failed.emit("Already in a lobby")
		return

	print("LobbyManager: Creating lobby for %d players..." % max_players)
	@warning_ignore("unsafe_method_access")
	_steam.createLobby(LOBBY_TYPE_PUBLIC, max_players)


func join_lobby(lobby_id: int) -> void:
	if _steam == null:
		lobby_join_failed.emit("Steam not initialized")
		return

	if current_lobby_id != 0:
		lobby_join_failed.emit("Already in a lobby")
		return

	print("LobbyManager: Joining lobby %d..." % lobby_id)
	@warning_ignore("unsafe_method_access")
	_steam.joinLobby(lobby_id)


func leave_lobby() -> void:
	if current_lobby_id == 0:
		return

	if _steam != null:
		print("LobbyManager: Leaving lobby %d" % current_lobby_id)
		@warning_ignore("unsafe_method_access")
		_steam.leaveLobby(current_lobby_id)

	current_lobby_id = 0
	is_host = false
	lobby_left.emit()


func request_lobby_list() -> void:
	if _steam == null:
		lobby_list_received.emit([])
		return

	print("LobbyManager: Requesting lobby list...")
	# Filter to only show lobbies for our app
	@warning_ignore("unsafe_method_access")
	_steam.addRequestLobbyListDistanceFilter(LOBBY_DISTANCE_WORLDWIDE)
	@warning_ignore("unsafe_method_access")
	_steam.requestLobbyList()


func set_lobby_metadata(key: String, value: String) -> bool:
	if _steam == null or current_lobby_id == 0 or not is_host:
		return false
	@warning_ignore("unsafe_method_access")
	return _steam.setLobbyData(current_lobby_id, key, value)


func get_lobby_metadata(lobby_id: int, key: String) -> String:
	if _steam == null:
		return ""
	@warning_ignore("unsafe_method_access")
	return _steam.getLobbyData(lobby_id, key)


func get_lobby_member_count(lobby_id: int) -> int:
	if _steam == null:
		return 0
	@warning_ignore("unsafe_method_access")
	return _steam.getNumLobbyMembers(lobby_id)


func get_lobby_owner(lobby_id: int) -> int:
	if _steam == null:
		return 0
	@warning_ignore("unsafe_method_access")
	return _steam.getLobbyOwner(lobby_id)


func get_lobby_members(lobby_id: int) -> Array[int]:
	var members: Array[int] = []
	if _steam == null:
		return members

	@warning_ignore("unsafe_method_access")
	var count: int = _steam.getNumLobbyMembers(lobby_id)
	for i in range(count):
		@warning_ignore("unsafe_method_access")
		members.append(_steam.getLobbyMemberByIndex(lobby_id, i))
	return members


func request_lobby_data(lobby_id: int) -> void:
	## Request data for a lobby to check if it still exists.
	## Emits lobby_data_received when complete.
	if _steam == null:
		lobby_data_received.emit(lobby_id, false)
		return

	if lobby_id <= 0:
		lobby_data_received.emit(lobby_id, false)
		return

	print("LobbyManager: Requesting data for lobby %d" % lobby_id)
	_pending_lobby_data_requests.append(lobby_id)
	@warning_ignore("unsafe_method_access")
	var success: bool = _steam.requestLobbyData(lobby_id)
	if not success:
		_pending_lobby_data_requests.erase(lobby_id)
		lobby_data_received.emit(lobby_id, false)


func is_lobby_data_pending(lobby_id: int) -> bool:
	## Check if we're waiting for data from a specific lobby.
	return lobby_id in _pending_lobby_data_requests


func find_lobby_by_owner(steam_id: int, callback: Callable) -> void:
	## Find a town lobby by owner Steam ID.
	## Queries Steam lobby list filtered by owner_steam_id metadata.
	## Calls callback(lobby_id: int) when done - 0 means not found.
	if _steam == null or _is_finding_lobby or _is_finding_field:
		callback.call(0)
		return

	_find_lobby_callback = callback
	_find_lobby_steam_id = steam_id
	_is_finding_lobby = true

	print("LobbyManager: Searching for town owned by %d..." % steam_id)

	# Filter by owner_steam_id and server_type = town
	@warning_ignore("unsafe_method_access")
	_steam.addRequestLobbyListStringFilter(
		"owner_steam_id", str(steam_id), LOBBY_COMPARISON_EQUAL
	)
	@warning_ignore("unsafe_method_access")
	_steam.addRequestLobbyListStringFilter(
		"server_type", "town", LOBBY_COMPARISON_EQUAL
	)
	@warning_ignore("unsafe_method_access")
	_steam.addRequestLobbyListDistanceFilter(LOBBY_DISTANCE_WORLDWIDE)
	@warning_ignore("unsafe_method_access")
	_steam.requestLobbyList()


func find_field_by_seed(
	generation_seed: int, callback: Callable
) -> void:
	## Find an active field lobby by generation seed.
	## Queries Steam lobby list filtered by server_type and generation_seed.
	## Calls callback(lobby_id: int) when done - 0 means not found.
	if _steam == null or _is_finding_lobby or _is_finding_field:
		callback.call(0)
		return

	_find_field_callback = callback
	_find_field_seed = generation_seed
	_is_finding_field = true

	print(
		"LobbyManager: Searching for field with seed %d..."
		% generation_seed
	)

	@warning_ignore("unsafe_method_access")
	_steam.addRequestLobbyListStringFilter(
		"server_type", "field", LOBBY_COMPARISON_EQUAL
	)
	@warning_ignore("unsafe_method_access")
	_steam.addRequestLobbyListStringFilter(
		"generation_seed", str(generation_seed),
		LOBBY_COMPARISON_EQUAL
	)
	@warning_ignore("unsafe_method_access")
	_steam.addRequestLobbyListDistanceFilter(LOBBY_DISTANCE_WORLDWIDE)
	@warning_ignore("unsafe_method_access")
	_steam.requestLobbyList()


# Steam callback handlers

func _on_lobby_created(result: int, lobby_id: int) -> void:
	if result != 1:  # 1 = k_EResultOK
		print("LobbyManager: Failed to create lobby, result: %d" % result)
		lobby_create_failed.emit("Steam error code: %d" % result)
		return

	current_lobby_id = lobby_id
	is_host = true

	print("LobbyManager: Lobby created successfully (ID: %d)" % lobby_id)

	# Set default metadata with sanitized username
	var sanitized_name: String = Utils.sanitize_display_string(SteamManager.get_steam_username())
	@warning_ignore("return_value_discarded")
	set_lobby_metadata("server_name", "%s's Server" % sanitized_name)

	lobby_created.emit(lobby_id)


func _on_lobby_joined(lobby_id: int, _permissions: int, _locked: bool, response: int) -> void:
	if response != 1:  # 1 = k_EChatRoomEnterResponseSuccess
		print("LobbyManager: Failed to join lobby, response: %d" % response)
		lobby_join_failed.emit("Join failed, code: %d" % response)
		return

	current_lobby_id = lobby_id
	is_host = (get_lobby_owner(lobby_id) == SteamManager.get_steam_id())

	print("LobbyManager: Joined lobby %d (host: %s)" % [lobby_id, is_host])
	lobby_joined.emit(lobby_id)


func _on_lobby_match_list(lobbies: Array) -> void:
	if _is_finding_field:
		_is_finding_field = false
		var found_id: int = 0
		for lobby_id: Variant in lobbies:
			if lobby_id is int:
				@warning_ignore("unsafe_cast")
				found_id = lobby_id as int
				break  # First match (filters already applied)
		print(
			"LobbyManager: Find-by-seed result: %d (searched %d lobbies)"
			% [found_id, lobbies.size()]
		)
		var cb: Callable = _find_field_callback
		_find_field_callback = Callable()
		_find_field_seed = 0
		if cb.is_valid():
			cb.call(found_id)
		return

	if _is_finding_lobby:
		_is_finding_lobby = false
		var found_id: int = 0
		for lobby_id: Variant in lobbies:
			if lobby_id is int:
				@warning_ignore("unsafe_cast")
				found_id = lobby_id as int
				break  # First match (filters already applied)
		print("LobbyManager: Find-by-owner result: %d (searched %d lobbies)" % [
			found_id, lobbies.size()
		])
		var cb: Callable = _find_lobby_callback
		_find_lobby_callback = Callable()
		_find_lobby_steam_id = 0
		if cb.is_valid():
			cb.call(found_id)
		return

	print("LobbyManager: Found %d lobbies" % lobbies.size())
	lobby_list_received.emit(lobbies)


func _on_lobby_data_update(success: int, lobby_id: int, _member_id: int) -> void:
	## Called when lobby data is received or fails.
	## success: 1 = success, 0 = failure (lobby doesn't exist or is not visible)
	if lobby_id in _pending_lobby_data_requests:
		_pending_lobby_data_requests.erase(lobby_id)
		var exists: bool = (success == 1)
		print("LobbyManager: Lobby %d data received (exists: %s)" % [lobby_id, exists])
		lobby_data_received.emit(lobby_id, exists)
