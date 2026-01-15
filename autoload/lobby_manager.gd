extends Node
## Manages Steam lobby creation, joining, leaving, and queries.
## Handles lobby metadata for server type and portal linking.

signal lobby_created(lobby_id: int)
signal lobby_create_failed(reason: String)
signal lobby_joined(lobby_id: int)
signal lobby_join_failed(reason: String)
signal lobby_left
signal lobby_list_received(lobbies: Array)

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
	print("LobbyManager: Found %d lobbies" % lobbies.size())
	lobby_list_received.emit(lobbies)
