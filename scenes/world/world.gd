extends Node3D
## Main game world scene.
## Handles player spawning, item spawning, and game state.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const PICKUP_RANGE: float = 3.0


static func _get_spawn_item_id(spawn_data: Dictionary) -> StringName:
	## Safely extract item_id from spawn data dictionary.
	## Note: @warning_ignore needed because GDScript doesn't track type narrowing from 'is' checks
	var value: Variant = spawn_data.get("item_id", "")
	if value is StringName:
		@warning_ignore("unsafe_cast")
		return value as StringName
	if value is String:
		@warning_ignore("unsafe_cast")
		return StringName(value as String)
	return &""


@onready var _spawn_points: Node3D = $SpawnPoints
@onready var _players_container: Node3D = $Players
@onready var _player_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var _item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var _status_label: Label = $UI/StatusLabel
@onready var _inventory_ui: InventoryUI = $UI/InventoryUI
@onready var _toast_ui: ToastUI = $UI/ToastUI

var _spawn_index: int = 0


func _ready() -> void:
	var role: String = "Server" if multiplayer.is_server() else "Client"
	var peer_id: int = multiplayer.get_unique_id()
	print("World: _ready() called - Role: %s, PeerID: %d" % [role, peer_id])

	# Configure the MultiplayerSpawner for players
	_player_spawner.spawn_function = _spawn_player

	# Configure the MultiplayerSpawner for items
	_item_spawner.spawn_function = _spawn_world_item

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

	# Connect inventory signals
	@warning_ignore("return_value_discarded")
	InventoryManager.inventory_full.connect(_on_inventory_full)
	if _inventory_ui != null:
		@warning_ignore("return_value_discarded")
		_inventory_ui.drop_requested.connect(_on_drop_requested)

	# Spawn players
	if multiplayer.has_multiplayer_peer():
		print("World: Has multiplayer peer, is_server: %s" % multiplayer.is_server())
		if multiplayer.is_server():
			# Server: spawn self and any already-connected peers
			_spawn_all_connected_players()
			# Spawn initial test items
			_spawn_initial_items()
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
	if InventoryManager.inventory_full.is_connected(_on_inventory_full):
		InventoryManager.inventory_full.disconnect(_on_inventory_full)
	if _inventory_ui and _inventory_ui.drop_requested.is_connected(_on_drop_requested):
		_inventory_ui.drop_requested.disconnect(_on_drop_requested)


# =============================================================================
# Item Spawning
# =============================================================================

func _spawn_initial_items() -> void:
	## Server-only: Spawns initial test items in the world.
	if not multiplayer.is_server():
		return

	# Spawn air pearls for testing
	var air_pearl_positions: Array[Vector3] = [
		Vector3(2, 0, 2),
		Vector3(-2, 0, 2),
	]
	for pos: Vector3 in air_pearl_positions:
		_spawn_item_at(&"air_pearl", pos, 1)

	# Spawn flame pearls for testing
	var flame_pearl_positions: Array[Vector3] = [
		Vector3(0, 0, -2),
		Vector3(3, 0, -1),
	]
	for pos: Vector3 in flame_pearl_positions:
		_spawn_item_at(&"flame_pearl", pos, 1)


func _spawn_item_at(item_id: StringName, pos: Vector3, quantity: int = 1) -> void:
	## Server-only: Spawns a world item at the specified position.
	if not multiplayer.is_server():
		return

	var spawn_data: Dictionary = {
		"item_id": str(item_id),
		"position": pos,
		"quantity": quantity
	}
	@warning_ignore("return_value_discarded")
	_item_spawner.spawn(spawn_data)


func _spawn_world_item(data: Variant) -> Node:
	## Spawn function for the item MultiplayerSpawner.
	if not data is Dictionary:
		push_error("World: Invalid item spawn data")
		return null

	var spawn_data: Dictionary = data
	var item_id: StringName = _get_spawn_item_id(spawn_data)
	var pos: Vector3 = spawn_data.get("position", Vector3.ZERO)
	var quantity: int = spawn_data.get("quantity", 1)

	var item_data: ItemData = InventoryManager.get_item_data(item_id)
	if item_data == null or item_data.world_scene == null:
		push_error("World: Unknown item or no world scene: %s" % item_id)
		return null

	var world_item: WorldItem = item_data.world_scene.instantiate()
	if world_item == null:
		push_error("World: Failed to instantiate world item: %s" % item_id)
		return null

	world_item.item_id = item_id
	world_item.quantity = quantity
	world_item.position = pos

	# Connect pickup signal
	@warning_ignore("return_value_discarded")
	world_item.picked_up.connect(_on_world_item_picked_up.bind(world_item))

	return world_item


func _on_world_item_picked_up(player: Node3D, world_item: WorldItem) -> void:
	## Called when a player interacts with a world item.
	## Only the local player triggers this, then requests pickup from server.
	if player == null or world_item == null:
		return

	# Only process for the local player
	if not player.is_multiplayer_authority():
		return

	# Request pickup from server
	var item_path: String = str(world_item.get_path())
	if multiplayer.is_server():
		# Server picks up directly - pass own peer ID
		_process_pickup(1, item_path)
	else:
		_request_pickup.rpc_id(1, item_path)


# =============================================================================
# Item Pickup/Drop RPCs
# =============================================================================

@rpc("any_peer", "call_remote", "reliable")
func _request_pickup(item_path: String) -> void:
	## Client requests to pick up an item. Server validates and confirms.
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_process_pickup(sender_id, item_path)


func _process_pickup(peer_id: int, item_path: String) -> void:
	## Server-only: Process a pickup request from a peer.
	var world_item: WorldItem = get_node_or_null(item_path)

	if world_item == null:
		print("World: Pickup request failed - item not found: %s" % item_path)
		return

	# Validate player is in range
	var player_node: Node3D = _players_container.get_node_or_null(str(peer_id))
	if player_node == null:
		print("World: Pickup request failed - player not found: %d" % peer_id)
		return

	var distance: float = player_node.global_position.distance_to(world_item.global_position)
	if distance > PICKUP_RANGE:
		print("World: Pickup request failed - player too far: %.1f > %.1f" % [distance, PICKUP_RANGE])
		return

	# Pickup is valid - get item info before destroying
	var item_id: StringName = world_item.item_id
	var quantity: int = world_item.quantity

	# Remove the world item
	world_item.queue_free()

	# Confirm pickup to the requesting peer
	if peer_id == 1:
		# Server picks up locally
		_add_pickup_to_inventory(item_id, quantity)
	else:
		# Remote client - send confirmation via RPC
		_confirm_pickup.rpc_id(peer_id, str(item_id), quantity)


@rpc("authority", "call_remote", "reliable")
func _confirm_pickup(item_id_str: String, quantity: int) -> void:
	## Server confirms pickup. Client adds item to inventory.
	var item_id: StringName = StringName(item_id_str)
	_add_pickup_to_inventory(item_id, quantity)


func _add_pickup_to_inventory(item_id: StringName, quantity: int) -> void:
	## Add picked up item to local inventory. Handles overflow by requesting drop.
	var overflow: int = InventoryManager.add_item(item_id, quantity)

	if overflow > 0:
		print("World: Picked up %d %s, %d overflow" % [quantity - overflow, item_id, overflow])
		# Request server to spawn overflow back
		if multiplayer.is_server():
			_process_drop(1, str(item_id), overflow)
		else:
			_request_drop.rpc_id(1, str(item_id), overflow)
	else:
		print("World: Picked up %d %s" % [quantity, item_id])


@rpc("any_peer", "call_remote", "reliable")
func _request_drop(item_id_str: String, quantity: int) -> void:
	## Client requests to drop an item. Server spawns the world item.
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_process_drop(sender_id, item_id_str, quantity)


func _process_drop(peer_id: int, item_id_str: String, quantity: int) -> void:
	## Server-only: Process a drop request from a peer.
	var player_node: Node3D = _players_container.get_node_or_null(str(peer_id))

	if player_node == null:
		print("World: Drop request failed - player not found: %d" % peer_id)
		return

	# Calculate drop position (in front of player, at ground level)
	var drop_pos: Vector3 = player_node.global_position
	var forward: Vector3 = -player_node.global_transform.basis.z
	drop_pos += forward * 1.0  # 1 unit in front
	drop_pos.y = 0.0  # Ground level

	var item_id: StringName = StringName(item_id_str)
	_spawn_item_at(item_id, drop_pos, quantity)
	print("World: Dropped %d %s at %s" % [quantity, item_id, drop_pos])


func _on_drop_requested(item_id: StringName, quantity: int) -> void:
	## Called when player drops item from inventory UI.
	if multiplayer.is_server():
		_process_drop(1, str(item_id), quantity)
	else:
		_request_drop.rpc_id(1, str(item_id), quantity)


func _on_inventory_full() -> void:
	## Called when inventory is full and item couldn't be added.
	if _toast_ui != null:
		_toast_ui.show_toast("Inventory Full")
