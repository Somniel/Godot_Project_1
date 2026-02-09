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
signal disconnected
signal gateway_state_received(gateway_id: int, data: Dictionary)

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

	print(
		(
			"NetworkManager: Connecting to host %d in lobby %d"
			% [host_steam_id, LobbyManager.current_lobby_id]
		)
	)

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
	disconnected.emit()


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
	print(
		"NetworkManager: Peer connected: %d (I am peer %d)" % [peer_id, multiplayer.get_unique_id()]
	)
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


# Gateway sync RPCs

@rpc("authority", "call_remote", "reliable")
func sync_gateway_state(
	gateway_id: int,
	linked_lobby_id: int,
	linked_map_name: String,
	generation_seed: int,
	pearl_type: String,
	linked_gateway_id: int,
	link_type: String = "none",
	linked_owner_steam_id: int = 0
) -> void:
	## Called on clients by server to sync a gateway's state.
	var data: Dictionary = {
		"linked_lobby_id": linked_lobby_id,
		"linked_map_name": linked_map_name,
		"generation_seed": generation_seed,
		"pearl_type": pearl_type,
		"linked_gateway_id": linked_gateway_id,
		"link_type": link_type,
		"linked_owner_steam_id": linked_owner_steam_id
	}
	gateway_state_received.emit(gateway_id, data)


func broadcast_gateway_state(
	gateway_id: int,
	linked_lobby_id: int,
	linked_map_name: String,
	generation_seed: int,
	pearl_type: StringName,
	linked_gateway_id: int = -1,
	link_type: String = "field",
	linked_owner_steam_id: int = 0
) -> void:
	## Called by server to broadcast gateway state to all connected clients.
	if not multiplayer.is_server():
		return

	sync_gateway_state.rpc(
		gateway_id,
		linked_lobby_id,
		linked_map_name,
		generation_seed,
		String(pearl_type),
		linked_gateway_id,
		link_type,
		linked_owner_steam_id
	)


func sync_gateway_state_to_peer(
	peer_id: int,
	gateway_id: int,
	linked_lobby_id: int,
	linked_map_name: String,
	generation_seed: int,
	pearl_type: StringName,
	linked_gateway_id: int = -1,
	link_type: String = "field",
	linked_owner_steam_id: int = 0
) -> void:
	## Called by server to sync gateway state to a specific peer (e.g., on join).
	if not multiplayer.is_server():
		return

	sync_gateway_state.rpc_id(
		peer_id,
		gateway_id,
		linked_lobby_id,
		linked_map_name,
		generation_seed,
		String(pearl_type),
		linked_gateway_id,
		link_type,
		linked_owner_steam_id
	)


# Client-to-server gateway configuration request

## Emitted on server when a client requests to configure a gateway
signal client_gateway_config_requested(
	peer_id: int, gateway_id: int, generation_seed: int, field_name: String, pearl_type: String
)

@rpc("any_peer", "call_remote", "reliable")
func request_gateway_config(
	gateway_id: int, generation_seed: int, field_name: String, pearl_type: String
) -> void:
	## Called by client to request the server configure a gateway.
	## Server will validate and broadcast the change to all clients.
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	print(
		(
			"NetworkManager: Gateway config request from peer %d for gateway %d"
			% [sender_id, gateway_id]
		)
	)
	client_gateway_config_requested.emit(
		sender_id, gateway_id, generation_seed, field_name, pearl_type
	)


func send_gateway_config_request(
	gateway_id: int, generation_seed: int, field_name: String, pearl_type: StringName
) -> void:
	## Called by client to send a gateway configuration request to the server.
	if multiplayer.is_server():
		return  # Server doesn't need to send requests to itself

	request_gateway_config.rpc_id(1, gateway_id, generation_seed, field_name, String(pearl_type))


## Emitted on client when server confirms a gateway configuration
signal gateway_config_confirmed(
	gateway_id: int, generation_seed: int, field_name: String, pearl_type: String
)

## Emitted on client when server rejects a gateway configuration
signal gateway_config_rejected(gateway_id: int, reason: String)

@rpc("authority", "call_remote", "reliable")
func confirm_gateway_config(
	gateway_id: int, generation_seed: int, field_name: String, pearl_type: String
) -> void:
	## Called on client by server to confirm a gateway configuration.
	gateway_config_confirmed.emit(gateway_id, generation_seed, field_name, pearl_type)


@rpc("authority", "call_remote", "reliable")
func reject_gateway_config(gateway_id: int, reason: String) -> void:
	## Called on client by server to reject a gateway configuration.
	gateway_config_rejected.emit(gateway_id, reason)


func send_gateway_config_confirmation(
	peer_id: int, gateway_id: int, generation_seed: int, field_name: String, pearl_type: StringName
) -> void:
	## Called by server to confirm a gateway config to the requesting client.
	if not multiplayer.is_server():
		return
	confirm_gateway_config.rpc_id(
		peer_id, gateway_id, generation_seed, field_name, String(pearl_type)
	)


func send_gateway_config_rejection(peer_id: int, gateway_id: int, reason: String) -> void:
	## Called by server to reject a gateway config request.
	if not multiplayer.is_server():
		return
	reject_gateway_config.rpc_id(peer_id, gateway_id, reason)


# =============================================================================
# Field State Cache Sync RPCs
# =============================================================================

## Emitted when cache data is received from network
signal field_cache_received(entries: Array, remappings: Dictionary)

@rpc("authority", "call_remote", "reliable")
func sync_field_cache(entries_json: String, remappings_json: String) -> void:
	## Called on clients by server to sync field cache entries.
	var entries: Array = []
	var remappings: Dictionary = {}

	# Parse entries JSON
	var parsed_entries: Variant = JSON.parse_string(entries_json)
	if parsed_entries is Array:
		@warning_ignore("unsafe_cast")
		entries = parsed_entries as Array

	# Parse remappings JSON
	var parsed_remappings: Variant = JSON.parse_string(remappings_json)
	if parsed_remappings is Dictionary:
		@warning_ignore("unsafe_cast")
		remappings = parsed_remappings as Dictionary

	print(
		(
			"NetworkManager: Received field cache sync (%d entries, %d remappings)"
			% [entries.size(), remappings.size()]
		)
	)
	field_cache_received.emit(entries, remappings)


func broadcast_field_cache(entries: Array[Dictionary], remappings: Dictionary) -> void:
	## Called by server to broadcast field cache to all connected clients.
	if not multiplayer.is_server():
		return

	var entries_json: String = JSON.stringify(entries)
	var remappings_json: String = JSON.stringify(remappings)
	sync_field_cache.rpc(entries_json, remappings_json)
	print(
		(
			"NetworkManager: Broadcast field cache (%d entries, %d remappings)"
			% [entries.size(), remappings.size()]
		)
	)


func sync_field_cache_to_peer(
	peer_id: int, entries: Array[Dictionary], remappings: Dictionary
) -> void:
	## Called by server to sync field cache to a specific peer (e.g., on join).
	if not multiplayer.is_server():
		return

	var entries_json: String = JSON.stringify(entries)
	var remappings_json: String = JSON.stringify(remappings)
	sync_field_cache.rpc_id(peer_id, entries_json, remappings_json)
	print(
		(
			"NetworkManager: Sent field cache to peer %d (%d entries, %d remappings)"
			% [peer_id, entries.size(), remappings.size()]
		)
	)


# =============================================================================
# Field State Version Exchange RPCs
# =============================================================================

## Emitted when a peer sends their field state version
signal field_version_received(
	peer_id: int, generation_seed: int, version: int, modifier_steam_id: int
)

## Emitted when a peer requests field state
signal field_state_requested(peer_id: int, generation_seed: int)

## Emitted when field state is received from a peer
signal field_state_received(sender_id: int, generation_seed: int, state_json: String)

@rpc("any_peer", "call_remote", "reliable")
func exchange_field_version(generation_seed: int, version: int, modifier_steam_id: int) -> void:
	## Called to exchange field state versions between peers.
	## Both host and clients can call this to share their version.
	var sender_id: int = multiplayer.get_remote_sender_id()
	print(
		(
			"NetworkManager: Received field version from peer %d (seed %d, v%d, modifier %d)"
			% [sender_id, generation_seed, version, modifier_steam_id]
		)
	)
	field_version_received.emit(sender_id, generation_seed, version, modifier_steam_id)


@rpc("any_peer", "call_remote", "reliable")
func request_field_state(generation_seed: int) -> void:
	## Called by a peer to request full field state from another peer.
	## Typically called when the requester has an older version.
	var sender_id: int = multiplayer.get_remote_sender_id()
	print(
		(
			"NetworkManager: Field state request from peer %d for seed %d"
			% [sender_id, generation_seed]
		)
	)
	field_state_requested.emit(sender_id, generation_seed)


@rpc("any_peer", "call_remote", "reliable")
func send_field_state(generation_seed: int, state_json: String) -> void:
	## Called to send full field state to a peer who requested it.
	var sender_id: int = multiplayer.get_remote_sender_id()
	print(
		(
			"NetworkManager: Received field state from peer %d for seed %d"
			% [sender_id, generation_seed]
		)
	)
	field_state_received.emit(sender_id, generation_seed, state_json)


func broadcast_field_version(generation_seed: int, version: int, modifier_steam_id: int) -> void:
	## Called to broadcast field version to all peers.
	exchange_field_version.rpc(generation_seed, version, modifier_steam_id)


func send_field_version_to_peer(
	peer_id: int, generation_seed: int, version: int, modifier_steam_id: int
) -> void:
	## Called to send field version to a specific peer.
	exchange_field_version.rpc_id(peer_id, generation_seed, version, modifier_steam_id)


func send_field_state_to_peer(peer_id: int, generation_seed: int, state_json: String) -> void:
	## Called to send full field state to a specific peer.
	send_field_state.rpc_id(peer_id, generation_seed, state_json)


# =============================================================================
# Client Field Travel Approval RPCs
# =============================================================================

## Emitted on server when a client requests to travel through a gateway
signal field_travel_requested(peer_id: int, gateway_id: int)

## Emitted on client when server approves field travel with CRDT state
signal field_travel_approved(
	gateway_id: int,
	generation_seed: int,
	pearl_type: String,
	map_name: String,
	field_state_json: String,
	host_steam_id: int,
	existing_field_lobby: int
)

@rpc("any_peer", "call_remote", "reliable")
func request_field_travel(gateway_id: int) -> void:
	## Called by client to request travel through a configured gateway.
	## Server validates and responds with approve_field_travel.
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	print(
		"NetworkManager: Field travel request from peer %d for gateway %d" % [sender_id, gateway_id]
	)
	field_travel_requested.emit(sender_id, gateway_id)


@rpc("authority", "call_remote", "reliable")
func approve_field_travel(
	gateway_id: int,
	generation_seed: int,
	pearl_type: String,
	map_name: String,
	field_state_json: String,
	host_steam_id: int,
	existing_field_lobby: int
) -> void:
	## Called on client by server to approve field travel with CRDT state.
	print(
		(
			("NetworkManager: Field travel approved for gateway %d " + "(seed %d, existing=%d)")
			% [gateway_id, generation_seed, existing_field_lobby]
		)
	)
	field_travel_approved.emit(
		gateway_id,
		generation_seed,
		pearl_type,
		map_name,
		field_state_json,
		host_steam_id,
		existing_field_lobby
	)


# =============================================================================
# CRDT Field State Exchange RPCs (replaces version-based exchange)
# =============================================================================

## Emitted when a peer sends their CRDT field state
signal field_crdt_received(peer_id: int, generation_seed: int, state_json: String)

@rpc("any_peer", "call_remote", "reliable")
func exchange_field_crdt(generation_seed: int, state_json: String) -> void:
	## Called to exchange CRDT field state between peers.
	## Both host and clients call this — merge is commutative and idempotent.
	var sender_id: int = multiplayer.get_remote_sender_id()
	print(
		(
			"NetworkManager: Received CRDT exchange from peer %d for seed %d"
			% [sender_id, generation_seed]
		)
	)
	field_crdt_received.emit(sender_id, generation_seed, state_json)


func send_field_crdt_to_peer(peer_id: int, generation_seed: int, state_json: String) -> void:
	## Called to send CRDT field state to a specific peer.
	exchange_field_crdt.rpc_id(peer_id, generation_seed, state_json)


# =============================================================================
# Field State Return RPCs (player returns from field to town)
# =============================================================================

## Emitted on client when server requests field state on return
signal field_state_return_requested(seeds_json: String)

## Emitted on server when client returns field state
signal field_state_returned(peer_id: int, entries_json: String)

@rpc("authority", "call_remote", "reliable")
func request_field_state_on_return(seeds_json: String) -> void:
	## Called on client by server to request CRDT state for matching seeds.
	print("NetworkManager: Server requested field state for seeds: %s" % seeds_json)
	field_state_return_requested.emit(seeds_json)


@rpc("any_peer", "call_remote", "reliable")
func return_field_state(entries_json: String) -> void:
	## Called by client to return CRDT state to the server.
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	print("NetworkManager: Received field state return from peer %d" % sender_id)
	field_state_returned.emit(sender_id, entries_json)


func send_field_travel_approval(
	peer_id: int,
	gateway_id: int,
	generation_seed: int,
	pearl_type: StringName,
	map_name: String,
	field_state_json: String,
	host_steam_id: int,
	existing_field_lobby: int
) -> void:
	## Called by server to approve a client's field travel request.
	if not multiplayer.is_server():
		return
	approve_field_travel.rpc_id(
		peer_id,
		gateway_id,
		generation_seed,
		String(pearl_type),
		map_name,
		field_state_json,
		host_steam_id,
		existing_field_lobby
	)


# =============================================================================
# Staged Field Lobby Report RPCs
# =============================================================================

## Emitted on server when a client reports a newly created field lobby
signal staged_field_lobby_reported(peer_id: int, gateway_id: int, lobby_id: int)

@rpc("any_peer", "call_remote", "reliable")
func report_staged_field_lobby(gateway_id: int, lobby_id: int) -> void:
	## Called by client to report a newly created field lobby to the server.
	## Server validates the sender against the approved creator.
	if not multiplayer.is_server():
		return
	var sender_id: int = multiplayer.get_remote_sender_id()
	print(
		(
			"NetworkManager: Staged field report from peer %d " % sender_id
			+ "(gateway %d, lobby %d)" % [gateway_id, lobby_id]
		)
	)
	staged_field_lobby_reported.emit(sender_id, gateway_id, lobby_id)


func get_steam_id_for_peer(peer_id: int) -> int:
	## Get the Steam 64-bit ID for a connected Godot peer.
	## Uses SteamMultiplayerPeer.get_steam64_from_peer_id().
	## Returns 0 if unavailable (no Steam, peer disconnected, etc.).
	if _multiplayer_peer == null:
		return 0
	if not _multiplayer_peer.has_method("get_steam64_from_peer_id"):
		return 0
	@warning_ignore("unsafe_method_access")
	var result: Variant = _multiplayer_peer.get_steam64_from_peer_id(peer_id)
	if result is int:
		@warning_ignore("unsafe_cast")
		return result as int
	return 0
