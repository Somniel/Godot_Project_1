extends Node3D
## Base class for map scenes (Town and Field).
## Contains shared logic for player spawning, item pickup/drop, peer lifecycle,
## and signal management. Subclasses override virtual methods for map-specific behavior.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const GATEWAY_SCENE: PackedScene = preload("res://scenes/world/gateway/gateway.tscn")
const PICKUP_RANGE: float = 3.0

## Gateway positions (N, E, S, W) - distance from center
const GATEWAY_DISTANCE: float = 15.0
const GATEWAY_POSITIONS: Array[Vector3] = [
	Vector3(0, 0, -GATEWAY_DISTANCE),   # North
	Vector3(GATEWAY_DISTANCE, 0, 0),    # East
	Vector3(0, 0, GATEWAY_DISTANCE),    # South
	Vector3(-GATEWAY_DISTANCE, 0, 0),   # West
]
const GATEWAY_ROTATIONS: Array[float] = [
	0.0,    # North - facing south (toward center)
	-90.0,  # East - facing west
	180.0,  # South - facing north
	90.0,   # West - facing east
]


static func _get_spawn_item_id(spawn_data: Dictionary) -> StringName:
	## Safely extract item_id from spawn data dictionary.
	var value: Variant = spawn_data.get("item_id", "")
	if value is StringName:
		@warning_ignore("unsafe_cast")
		return value as StringName
	if value is String:
		@warning_ignore("unsafe_cast")
		return StringName(value as String)
	return &""


# =============================================================================
# Shared Scene Node References
# =============================================================================
# These reference nodes that exist in both field.tscn and town.tscn with
# identical paths. Subclass-specific nodes are declared in the subclass.

@onready var _spawn_points: Node3D = $SpawnPoints
@onready var _players_container: Node3D = $Players
@onready var _player_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var _item_spawner: MultiplayerSpawner = $ItemSpawner
# Used by subclasses (town.gd, field.gd) for status display
@warning_ignore("unused_private_class_variable")
@onready var _status_label: Label = $UI/StatusLabel
@onready var _inventory_ui: InventoryUI = $UI/InventoryUI
@onready var _toast_ui: ToastUI = $UI/ToastUI
# Used by subclasses (town.gd, field.gd) to parent gateway nodes
@warning_ignore("unused_private_class_variable")
@onready var _gateways_container: Node3D = $Gateways
@onready var _gateway_config_dialog: GatewayConfigDialog = $UI/GatewayConfigDialog
@onready var _totem_ui: TotemUI = $UI/TotemUI
@onready var _totem_interactable: Interactable = $Environment/Totem/Interactable
@onready var _travel_confirm_dialog: TravelConfirmDialog = $UI/TravelConfirmDialog


# =============================================================================
# Shared State
# =============================================================================

var _spawn_index: int = 0
var _gateways: Array[Gateway] = []
var _pending_gateway_config: Gateway = null
var _pending_travel_gateway: Gateway = null
var _pending_travel_lobby_id: int = 0
## Tracks items currently being picked up (path -> true) to prevent duplicate
## pickups in the same frame. Entries are removed when the item leaves the tree.
var _pending_pickups: Dictionary = {}


# =============================================================================
# Virtual Methods (override in subclasses)
# =============================================================================

func _get_map_type_name() -> String:
	## Return "Field" or "Town" for log messages.
	return "Map"


func _get_arrival_gateway_id() -> int:
	## Determine which gateway the host arrived through.
	## Priority:
	## 1. Explicit target_gateway_id (from linked_gateway_id)
	## 2. Gateway that links to source lobby
	## Subclasses may override to add additional lookup sources.

	# Check for explicit target gateway first (set via linked_gateway_id)
	var target_gateway: int = MapManager.get_target_gateway_id()
	if target_gateway >= 0 and target_gateway < 4:
		print("%s: Using explicit target gateway %d" % [_get_map_type_name(), target_gateway])
		return target_gateway

	var source_lobby: int = MapManager.get_source_lobby_id()

	if source_lobby <= 0:
		return -1

	# Find which gateway links to the source lobby
	for i: int in range(_gateways.size()):
		var gateway: Gateway = _gateways[i]
		if gateway.linked_lobby_id == source_lobby:
			print("%s: Found gateway %d linking to source lobby" % [
				_get_map_type_name(), i
			])
			return i

	return -1


func _update_status() -> void:
	## Update the status label. Subclasses override for different formats.
	pass


func _on_peer_connected(peer_id: int) -> void:
	## Called when a peer connects. Subclasses override to add sync behavior.
	## Subclass overrides should call super() to get base spawning behavior.
	print("%s: Peer connected: %d" % [_get_map_type_name(), peer_id])
	if multiplayer.is_server():
		if not _is_player_spawned(peer_id):
			@warning_ignore("return_value_discarded")
			_player_spawner.spawn(peer_id)
	_update_status()


# =============================================================================
# Signal Management
# =============================================================================

func _connect_shared_signals() -> void:
	## Connect signals shared between all map types.
	## Called by subclass _ready() before connecting map-specific signals.

	# Spawner setup
	_player_spawner.spawn_function = _spawn_player
	_item_spawner.spawn_function = _spawn_world_item

	# Network signals
	@warning_ignore("return_value_discarded")
	multiplayer.peer_connected.connect(_on_peer_connected)
	@warning_ignore("return_value_discarded")
	multiplayer.peer_disconnected.connect(_on_peer_disconnected)
	@warning_ignore("return_value_discarded")
	multiplayer.server_disconnected.connect(_on_server_disconnected)

	# Spawner and container signals
	@warning_ignore("return_value_discarded")
	_player_spawner.spawned.connect(_on_player_spawned)
	@warning_ignore("return_value_discarded")
	_players_container.child_entered_tree.connect(_on_player_added)
	@warning_ignore("return_value_discarded")
	_players_container.child_exiting_tree.connect(_on_player_removed)

	# Inventory signals
	@warning_ignore("return_value_discarded")
	InventoryManager.inventory_full.connect(_on_inventory_full)
	if _inventory_ui != null:
		@warning_ignore("return_value_discarded")
		_inventory_ui.drop_requested.connect(_on_drop_requested)

	# Gateway config dialog signals
	if _gateway_config_dialog != null:
		@warning_ignore("return_value_discarded")
		_gateway_config_dialog.gateway_configured.connect(_on_gateway_configured)
		@warning_ignore("return_value_discarded")
		_gateway_config_dialog.cancelled.connect(_on_gateway_config_cancelled)

	# Totem interaction
	if _totem_interactable != null:
		@warning_ignore("return_value_discarded")
		_totem_interactable.interacted.connect(_on_totem_interacted)
	if _totem_ui != null:
		@warning_ignore("return_value_discarded")
		_totem_ui.gateway_clear_requested.connect(_on_gateway_clear_requested)

	# Travel confirmation dialog
	if _travel_confirm_dialog != null:
		@warning_ignore("return_value_discarded")
		_travel_confirm_dialog.confirmed.connect(_on_travel_confirm_confirmed)
		@warning_ignore("return_value_discarded")
		_travel_confirm_dialog.cancelled.connect(_on_travel_confirm_cancelled)

	# Lobby manager signals for gateway validation
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_data_received.connect(_on_lobby_data_received)

	# Network manager signals for gateway sync
	@warning_ignore("return_value_discarded")
	NetworkManager.gateway_state_received.connect(_on_gateway_state_received)


func _disconnect_shared_signals() -> void:
	## Disconnect signals shared between all map types.
	## Called by subclass _exit_tree() before disconnecting map-specific signals.
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
	if NetworkManager.gateway_state_received.is_connected(_on_gateway_state_received):
		NetworkManager.gateway_state_received.disconnect(_on_gateway_state_received)
	if LobbyManager.lobby_data_received.is_connected(_on_lobby_data_received):
		LobbyManager.lobby_data_received.disconnect(_on_lobby_data_received)


# =============================================================================
# Player Spawning
# =============================================================================

func _spawn_all_connected_players() -> void:
	print("%s: Spawning all connected players..." % _get_map_type_name())

	@warning_ignore("return_value_discarded")
	_player_spawner.spawn(1)

	var peers: PackedInt32Array = multiplayer.get_peers()
	for peer_id in peers:
		if peer_id != 1:
			print("%s: Spawning existing peer: %d" % [_get_map_type_name(), peer_id])
			@warning_ignore("return_value_discarded")
			_player_spawner.spawn(peer_id)


func _is_player_spawned(peer_id: int) -> bool:
	return _players_container.has_node(str(peer_id))


func _spawn_player(peer_id: int) -> Node:
	var role: String = "Server" if multiplayer.is_server() else "Client"
	print("%s: _spawn_player() called for peer %d (I am %s)" % [
		_get_map_type_name(), peer_id, role
	])

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	if player == null:
		push_error("%s: Failed to instantiate player scene for peer %d" % [
			_get_map_type_name(), peer_id
		])
		return null

	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	# Determine spawn position
	var spawn_point: Vector3
	if peer_id == 1:
		# Host: spawn near arrival gateway if we traveled here
		spawn_point = _get_host_spawn_point()
	else:
		# Other players: use default spawn points
		spawn_point = _get_next_spawn_point()

	player.position = spawn_point

	print("%s: Created player node '%s' at position %s" % [
		_get_map_type_name(), player.name, spawn_point
	])
	return player


func _get_host_spawn_point() -> Vector3:
	## Get spawn point for the host, considering travel source.
	var arrival_gateway_id: int = _get_arrival_gateway_id()

	if arrival_gateway_id >= 0 and arrival_gateway_id < GATEWAY_POSITIONS.size():
		# Spawn near the arrival gateway, offset toward center
		var gateway_pos: Vector3 = GATEWAY_POSITIONS[arrival_gateway_id]
		var direction_to_center: Vector3 = -gateway_pos.normalized()
		var spawn_pos: Vector3 = gateway_pos + direction_to_center * 3.0
		spawn_pos.y = 1.0
		print("%s: Host spawning near gateway %d at %s" % [
			_get_map_type_name(), arrival_gateway_id, spawn_pos
		])
		MapManager.clear_travel_source()
		return spawn_pos

	# No travel info - use default spawn
	return _get_next_spawn_point()


func _get_next_spawn_point() -> Vector3:
	var spawn_children := _spawn_points.get_children()
	if spawn_children.is_empty():
		return Vector3(0, 1, 0)

	var point: Marker3D = spawn_children[_spawn_index % spawn_children.size()]
	_spawn_index += 1
	return point.global_position


func _on_player_spawned(node: Node) -> void:
	print("%s: Player spawned: %s" % [_get_map_type_name(), node.name])
	_update_status()


func _on_player_added(_node: Node) -> void:
	_update_status()


func _on_player_removed(_node: Node) -> void:
	call_deferred("_update_status")


# =============================================================================
# Peer Lifecycle
# =============================================================================

func _on_peer_disconnected(peer_id: int) -> void:
	print("%s: Peer disconnected: %d" % [_get_map_type_name(), peer_id])
	var player_node := _players_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
	_update_status()


func _on_server_disconnected() -> void:
	print("%s: Server disconnected" % _get_map_type_name())
	_return_to_menu()


func _on_leave_button_pressed() -> void:
	_return_to_menu()


func _return_to_menu() -> void:
	NetworkManager.disconnect_peer()
	LobbyManager.leave_lobby()
	@warning_ignore("return_value_discarded")
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


# =============================================================================
# Item Spawning & Pickup
# =============================================================================

func _spawn_item_at(item_id: StringName, pos: Vector3, quantity: int = 1) -> void:
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
	if not data is Dictionary:
		push_error("%s: Invalid item spawn data" % _get_map_type_name())
		return null

	var spawn_data: Dictionary = data
	var item_id: StringName = _get_spawn_item_id(spawn_data)
	var pos: Vector3 = spawn_data.get("position", Vector3.ZERO)
	var quantity: int = spawn_data.get("quantity", 1)

	var item_data: ItemData = InventoryManager.get_item_data(item_id)
	if item_data == null or item_data.world_scene == null:
		push_error("%s: Unknown item or no world scene: %s" % [
			_get_map_type_name(), item_id
		])
		return null

	var world_item: WorldItem = item_data.world_scene.instantiate()
	if world_item == null:
		push_error("%s: Failed to instantiate world item: %s" % [
			_get_map_type_name(), item_id
		])
		return null

	world_item.item_id = item_id
	world_item.quantity = quantity
	world_item.position = pos

	@warning_ignore("return_value_discarded")
	world_item.picked_up.connect(_on_world_item_picked_up.bind(world_item))

	return world_item


func _on_world_item_picked_up(player: Node3D, world_item: WorldItem) -> void:
	if player == null or world_item == null:
		return

	if not player.is_multiplayer_authority():
		return

	var item_path: String = str(world_item.get_path())
	if multiplayer.is_server():
		_process_pickup(1, item_path)
	else:
		_request_pickup.rpc_id(1, item_path)


@rpc("any_peer", "call_remote", "reliable")
func _request_pickup(item_path: String) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_process_pickup(sender_id, item_path)


func _process_pickup(peer_id: int, item_path: String) -> void:
	if _pending_pickups.has(item_path):
		return

	var world_item: WorldItem = get_node_or_null(item_path)

	if world_item == null:
		print("%s: Pickup request failed - item not found: %s" % [
			_get_map_type_name(), item_path
		])
		return

	var player_node: Node3D = _players_container.get_node_or_null(str(peer_id))
	if player_node == null:
		print("%s: Pickup request failed - player not found: %d" % [
			_get_map_type_name(), peer_id
		])
		return

	var distance: float = player_node.global_position.distance_to(
		world_item.global_position
	)
	if distance > PICKUP_RANGE:
		print("%s: Pickup request failed - player too far: %.1f > %.1f" % [
			_get_map_type_name(), distance, PICKUP_RANGE
		])
		return

	var item_id: StringName = world_item.item_id
	var quantity: int = world_item.quantity

	_pending_pickups[item_path] = true
	@warning_ignore("return_value_discarded")
	world_item.tree_exiting.connect(_on_pickup_item_exiting.bind(item_path))
	world_item.queue_free()

	if peer_id == 1:
		_add_pickup_to_inventory(item_id, quantity)
	else:
		_confirm_pickup.rpc_id(peer_id, str(item_id), quantity)


@rpc("authority", "call_remote", "reliable")
func _confirm_pickup(item_id_str: String, quantity: int) -> void:
	var item_id: StringName = StringName(item_id_str)
	_add_pickup_to_inventory(item_id, quantity)


func _add_pickup_to_inventory(item_id: StringName, quantity: int) -> void:
	var overflow: int = InventoryManager.add_item(item_id, quantity)

	if overflow > 0:
		print("%s: Picked up %d %s, %d overflow" % [
			_get_map_type_name(), quantity - overflow, item_id, overflow
		])
		if multiplayer.is_server():
			_process_drop(1, str(item_id), overflow)
		else:
			_request_drop.rpc_id(1, str(item_id), overflow)
	else:
		print("%s: Picked up %d %s" % [_get_map_type_name(), quantity, item_id])


@rpc("any_peer", "call_remote", "reliable")
func _request_drop(item_id_str: String, quantity: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_process_drop(sender_id, item_id_str, quantity)


func _process_drop(peer_id: int, item_id_str: String, quantity: int) -> void:
	var player_node: Node3D = _players_container.get_node_or_null(str(peer_id))

	if player_node == null:
		print("%s: Drop request failed - player not found: %d" % [
			_get_map_type_name(), peer_id
		])
		return

	var drop_pos: Vector3 = player_node.global_position
	var forward: Vector3 = -player_node.global_transform.basis.z
	drop_pos += forward * 1.0
	drop_pos.y = 0.0

	var item_id: StringName = StringName(item_id_str)
	_spawn_item_at(item_id, drop_pos, quantity)
	print("%s: Dropped %d %s at %s" % [
		_get_map_type_name(), quantity, item_id, drop_pos
	])


func _on_drop_requested(item_id: StringName, quantity: int) -> void:
	if multiplayer.is_server():
		_process_drop(1, str(item_id), quantity)
	else:
		_request_drop.rpc_id(1, str(item_id), quantity)


func _on_inventory_full() -> void:
	if _toast_ui != null:
		_toast_ui.show_toast("Inventory Full")


func _on_pickup_item_exiting(item_path: String) -> void:
	@warning_ignore("return_value_discarded")
	_pending_pickups.erase(item_path)


# =============================================================================
# Virtual Handlers (subclasses must override these)
# =============================================================================
# These are connected by _connect_shared_signals() but have map-specific logic.
# Subclasses MUST provide implementations.

func _on_gateway_configured(
	_generation_seed: int, _field_name: String, _pearl_type: StringName
) -> void:
	push_warning("%s: _on_gateway_configured not implemented" % _get_map_type_name())


func _on_gateway_config_cancelled() -> void:
	_pending_gateway_config = null


func _on_totem_interacted(_player: Node3D) -> void:
	push_warning("%s: _on_totem_interacted not implemented" % _get_map_type_name())


func _on_gateway_clear_requested(_gateway_id: int) -> void:
	push_warning("%s: _on_gateway_clear_requested not implemented" % _get_map_type_name())


func _on_travel_confirm_confirmed() -> void:
	push_warning("%s: _on_travel_confirm_confirmed not implemented" % _get_map_type_name())


func _on_travel_confirm_cancelled() -> void:
	_pending_travel_lobby_id = 0
	_pending_travel_gateway = null
	print("%s: Travel cancelled" % _get_map_type_name())


func _on_lobby_data_received(_lobby_id: int, _success: bool) -> void:
	push_warning("%s: _on_lobby_data_received not implemented" % _get_map_type_name())


func _on_gateway_state_received(_gateway_id: int, _data: Dictionary) -> void:
	push_warning("%s: _on_gateway_state_received not implemented" % _get_map_type_name())
