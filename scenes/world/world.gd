extends Node3D
## Main game world scene.
## Handles player spawning and game state.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")

@onready var _spawn_points: Node3D = $SpawnPoints
@onready var _players_container: Node3D = $Players
@onready var _player_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var _status_label: Label = $UI/StatusLabel

var _spawn_index: int = 0


func _ready() -> void:
	var role: String = "Server" if multiplayer.is_server() else "Client"
	var peer_id: int = multiplayer.get_unique_id()
	print("World: _ready() called - Role: %s, PeerID: %d" % [role, peer_id])

	# Configure the MultiplayerSpawner
	_player_spawner.spawn_function = _spawn_player

	# Connect network signals
	@warning_ignore("return_value_discarded")
	multiplayer.peer_connected.connect(_on_peer_connected)
	@warning_ignore("return_value_discarded")
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	@warning_ignore("return_value_discarded")
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Connect spawner and container signals to update status when players arrive
	@warning_ignore("return_value_discarded")
	_player_spawner.spawned.connect(_on_player_spawned)
	@warning_ignore("return_value_discarded")
	_players_container.child_entered_tree.connect(_on_player_added)
	@warning_ignore("return_value_discarded")
	_players_container.child_exiting_tree.connect(_on_player_removed)

	# Spawn players
	if multiplayer.has_multiplayer_peer():
		print("World: Has multiplayer peer, is_server: %s" % multiplayer.is_server())
		if multiplayer.is_server():
			# Server: spawn self and any already-connected peers
			_spawn_all_connected_players()
		else:
			# Client: Check if any players already exist (replicated before _ready)
			var existing_players: int = _players_container.get_child_count()
			print("World: Client found %d existing players" % existing_players)
		_update_status()
	else:
		print("World: No multiplayer peer!")


func _spawn_all_connected_players() -> void:
	## Server-only: Spawns players for all connected peers including self.
	## Handles case where peers connected before world scene loaded.
	print("World: Spawning all connected players...")

	# Spawn the server's own player (peer ID 1)
	@warning_ignore("return_value_discarded")
	_player_spawner.spawn(1)

	# Spawn any already-connected clients
	var peers: PackedInt32Array = multiplayer.get_peers()
	for peer_id in peers:
		if peer_id != 1:  # Don't re-spawn server
			print("World: Spawning existing peer: %d" % peer_id)
			@warning_ignore("return_value_discarded")
			_player_spawner.spawn(peer_id)


func _is_player_spawned(peer_id: int) -> bool:
	## Check if a player node already exists for this peer.
	return _players_container.has_node(str(peer_id))


func _spawn_player(peer_id: int) -> Node:
	var role: String = "Server" if multiplayer.is_server() else "Client"
	print("World: _spawn_player() called for peer %d (I am %s)" % [peer_id, role])

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	if player == null:
		push_error("World: Failed to instantiate player scene for peer %d" % peer_id)
		return null

	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	# Position at spawn point
	var spawn_point := _get_next_spawn_point()
	player.position = spawn_point

	print("World: Created player node '%s' at position %s" % [player.name, spawn_point])
	return player


func _get_next_spawn_point() -> Vector3:
	var spawn_children := _spawn_points.get_children()
	if spawn_children.is_empty():
		return Vector3(0, 1, 0)

	var point: Marker3D = spawn_children[_spawn_index % spawn_children.size()]
	_spawn_index += 1
	return point.global_position


func _update_status() -> void:
	if not is_inside_tree() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	var player_count: int = _players_container.get_child_count()
	var role: String = "Host" if multiplayer.is_server() else "Client"
	_status_label.text = "%s - %d player(s) connected" % [role, player_count]


func _on_player_spawned(node: Node) -> void:
	print("World: Player spawned: %s" % node.name)
	_update_status()


func _on_player_added(_node: Node) -> void:
	# Called when any child enters the Players container (including replicated players)
	_update_status()


func _on_player_removed(_node: Node) -> void:
	# Called when any child exits the Players container
	# Use call_deferred to get accurate count after removal
	call_deferred("_update_status")


func _on_peer_connected(peer_id: int) -> void:
	print("World: Peer connected: %d" % peer_id)
	if multiplayer.is_server() and not _is_player_spawned(peer_id):
		# Server spawns player for new peer (only if not already spawned)
		@warning_ignore("return_value_discarded")
		_player_spawner.spawn(peer_id)
	_update_status()


func _on_peer_disconnected(peer_id: int) -> void:
	print("World: Peer disconnected: %d" % peer_id)
	# Remove the disconnected player's node
	var player_node := _players_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
	_update_status()


func _on_server_disconnected() -> void:
	print("World: Server disconnected")
	_return_to_menu()


func _on_leave_button_pressed() -> void:
	_return_to_menu()


func _return_to_menu() -> void:
	# Clean up networking
	NetworkManager.disconnect_peer()
	LobbyManager.leave_lobby()

	# Return to main menu
	@warning_ignore("return_value_discarded")
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _exit_tree() -> void:
	# Disconnect all signals to prevent orphaned connections
	if multiplayer.peer_connected.is_connected(_on_peer_connected):
		multiplayer.peer_connected.disconnect(_on_peer_connected)
	if multiplayer.peer_disconnected.is_connected(_on_peer_disconnected):
		multiplayer.peer_disconnected.disconnect(_on_peer_disconnected)
	if multiplayer.server_disconnected.is_connected(_on_server_disconnected):
		multiplayer.server_disconnected.disconnect(_on_server_disconnected)
	if _player_spawner and _player_spawner.spawned.is_connected(_on_player_spawned):
		_player_spawner.spawned.disconnect(_on_player_spawned)
	if _players_container:
		if _players_container.child_entered_tree.is_connected(_on_player_added):
			_players_container.child_entered_tree.disconnect(_on_player_added)
		if _players_container.child_exiting_tree.is_connected(_on_player_removed):
			_players_container.child_exiting_tree.disconnect(_on_player_removed)
