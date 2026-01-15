extends Node
## Manages MultiplayerPeer setup and RPC coordination.
## Handles portal travel between servers.

signal peer_connected(peer_id: int)
signal peer_disconnected(peer_id: int)
signal server_disconnected
signal travel_requested(destination_lobby_id: int)
signal host_started
signal client_started
signal connection_failed(reason: String)

var _multiplayer_peer: MultiplayerPeer = null
var _is_networking_active: bool = false
var _client_connected: bool = false


func _ready() -> void:
	@warning_ignore("return_value_discarded")
	multiplayer.peer_connected.connect(_on_peer_connected)
	@warning_ignore("return_value_discarded")
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	@warning_ignore("return_value_discarded")
	multiplayer.server_disconnected.connect(_on_server_disconnected)
	@warning_ignore("return_value_discarded")
	multiplayer.connected_to_server.connect(_on_connected_to_server)
	@warning_ignore("return_value_discarded")
	multiplayer.connection_failed.connect(_on_connection_to_server_failed)

	# Listen for lobby events to coordinate networking
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_created.connect(_on_lobby_created)
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_joined.connect(_on_lobby_joined)
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_left.connect(_on_lobby_left)


func start_host() -> void:
	## Call this after lobby is created to start hosting.
	## Lobby must be created first via LobbyManager.
	if LobbyManager.current_lobby_id == 0:
		connection_failed.emit("No lobby created")
		return

	if not _is_steam_multiplayer_available():
		connection_failed.emit("SteamMultiplayerPeer not available")
		return

	print("NetworkManager: Starting host for lobby %d" % LobbyManager.current_lobby_id)

	_multiplayer_peer = ClassDB.instantiate("SteamMultiplayerPeer")
	@warning_ignore("unsafe_method_access")
	var error: int = _multiplayer_peer.create_host(0)

	if error != OK:
		print("NetworkManager: Failed to create host, error: %d" % error)
		connection_failed.emit("Failed to create host")
		_multiplayer_peer = null
		return

	multiplayer.multiplayer_peer = _multiplayer_peer
	_is_networking_active = true

	print("NetworkManager: Host started successfully")
	host_started.emit()


func start_client() -> void:
	## Call this after joining a lobby to connect as client.
	## Must have joined a lobby first via LobbyManager.
	if LobbyManager.current_lobby_id == 0:
		connection_failed.emit("No lobby joined")
		return

	if not _is_steam_multiplayer_available():
		connection_failed.emit("SteamMultiplayerPeer not available")
		return

	# Get the lobby owner's Steam ID to connect to
	var host_steam_id: int = LobbyManager.get_lobby_owner(LobbyManager.current_lobby_id)
	if host_steam_id == 0:
		connection_failed.emit("Could not find lobby host")
		return

	print("NetworkManager: Connecting to host %d in lobby %d" % [host_steam_id, LobbyManager.current_lobby_id])

	_multiplayer_peer = ClassDB.instantiate("SteamMultiplayerPeer")
	@warning_ignore("unsafe_method_access")
	var error: int = _multiplayer_peer.create_client(host_steam_id)

	if error != OK:
		print("NetworkManager: Failed to connect, error: %d" % error)
		connection_failed.emit("Failed to connect to host")
		_multiplayer_peer = null
		return

	multiplayer.multiplayer_peer = _multiplayer_peer
	_is_networking_active = true
	_client_connected = false

	# Don't emit client_started here - wait for connected_to_server signal
	print("NetworkManager: Client connection initiated, waiting for server...")


func disconnect_peer() -> void:
	if _multiplayer_peer != null:
		print("NetworkManager: Disconnecting peer")
		_multiplayer_peer.close()
		_multiplayer_peer = null

	multiplayer.multiplayer_peer = null
	_is_networking_active = false
	_client_connected = false


func is_server() -> bool:
	return multiplayer.is_server()


func is_active() -> bool:
	return _is_networking_active


func get_unique_id() -> int:
	return multiplayer.get_unique_id()


@rpc("authority", "call_remote", "reliable")
func request_travel_to_server(destination_lobby_id: int) -> void:
	## Called on client by server to initiate portal travel.
	travel_requested.emit(destination_lobby_id)


func send_travel_request(peer_id: int, destination_lobby_id: int) -> void:
	## Called by server to tell a specific client to travel.
	if multiplayer.is_server():
		request_travel_to_server.rpc_id(peer_id, destination_lobby_id)


func travel_to_server(destination_lobby_id: int) -> void:
	## Initiates travel to another server.
	## Disconnects from current, then joins new lobby.
	print("NetworkManager: Traveling to lobby %d" % destination_lobby_id)

	# Disconnect and leave current lobby
	disconnect_peer()
	LobbyManager.leave_lobby()

	# Join the destination lobby (networking starts via _on_lobby_joined)
	LobbyManager.join_lobby(destination_lobby_id)


func _is_steam_multiplayer_available() -> bool:
	return ClassDB.class_exists("SteamMultiplayerPeer")


# Lobby event handlers

func _on_lobby_created(_lobby_id: int) -> void:
	# Automatically start hosting when we create a lobby
	start_host()


func _on_lobby_joined(_lobby_id: int) -> void:
	# Start as client if we're not the host
	if not LobbyManager.is_host:
		start_client()


func _on_lobby_left() -> void:
	disconnect_peer()


# Multiplayer event handlers

func _on_peer_connected(peer_id: int) -> void:
	print("NetworkManager: Peer connected: %d (I am peer %d)" % [peer_id, multiplayer.get_unique_id()])
	peer_connected.emit(peer_id)

	# For clients: peer_id 1 connecting means we're connected to the server
	# This is a fallback in case connected_to_server doesn't fire with Steam P2P
	if not multiplayer.is_server() and peer_id == 1:
		print("NetworkManager: Client detected server connection via peer_connected")
		_on_connected_to_server()


func _on_peer_disconnected(peer_id: int) -> void:
	print("NetworkManager: Peer disconnected: %d" % peer_id)
	peer_disconnected.emit(peer_id)


func _on_server_disconnected() -> void:
	print("NetworkManager: Server disconnected")
	disconnect_peer()
	server_disconnected.emit()


func _on_connected_to_server() -> void:
	# Prevent double emission (can be called by both connected_to_server and peer_connected)
	if _client_connected:
		return
	_client_connected = true
	print("NetworkManager: Connected to server successfully")
	client_started.emit()


func _on_connection_to_server_failed() -> void:
	print("NetworkManager: Connection to server failed")
	disconnect_peer()
	connection_failed.emit("Connection to server failed")
