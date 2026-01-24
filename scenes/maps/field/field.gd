extends Node3D
## Field map scene - temporary procedurally generated map.
## Does not persist to Steam Cloud. Exists only while hosted or linked.

const PLAYER_SCENE: PackedScene = preload("res://scenes/player/player.tscn")
const GATEWAY_SCENE: PackedScene = preload("res://scenes/world/gateway/gateway.tscn")
const OBSTACLE_SCENE: PackedScene = preload("res://scenes/world/obstacle/obstacle.tscn")
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


@onready var _spawn_points: Node3D = $SpawnPoints
@onready var _players_container: Node3D = $Players
@onready var _player_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var _item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var _status_label: Label = $UI/StatusLabel
@onready var _inventory_ui: InventoryUI = $UI/InventoryUI
@onready var _toast_ui: ToastUI = $UI/ToastUI
@onready var _gateways_container: Node3D = $Gateways
@onready var _gateway_config_dialog: GatewayConfigDialog = $UI/GatewayConfigDialog
@onready var _obstacles_container: Node3D = $Obstacles
@onready var _ground_mesh: MeshInstance3D = $Environment/Ground/MeshInstance3D
@onready var _totem_ui: TotemUI = $UI/TotemUI
@onready var _totem_interactable: Interactable = $Environment/Totem/Interactable
@onready var _travel_confirm_dialog: TravelConfirmDialog = $UI/TravelConfirmDialog

var _spawn_index: int = 0
var _gateways: Array[Gateway] = []
var _pending_gateway_config: Gateway = null
var _pending_travel_gateway: Gateway = null
var _pending_travel_lobby_id: int = 0
var _pending_travel_is_town: bool = false
var _field_generator: ProceduralFieldGenerator = null

## Field generation seed (from lobby metadata)
var _generation_seed: int = 0

## Origin lobby ID (the map this field was created from)
var _origin_lobby_id: int = 0

## Origin gateway ID (which gateway in origin leads here)
var _origin_gateway: int = 0

## Name of the origin map (for return gateway display)
var _origin_map_name: String = ""

## Pearl type used to create this field (determines theme)
var _pearl_type: StringName = &""


func _ready() -> void:
	var role: String = "Server" if multiplayer.is_server() else "Client"
	var peer_id: int = multiplayer.get_unique_id()
	print("Field: _ready() called - Role: %s, PeerID: %d" % [role, peer_id])

	# Read field metadata
	_read_field_metadata()

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

	# Connect spawner and container signals
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

	# Connect gateway config dialog signals
	if _gateway_config_dialog != null:
		@warning_ignore("return_value_discarded")
		_gateway_config_dialog.gateway_configured.connect(_on_gateway_configured)
		@warning_ignore("return_value_discarded")
		_gateway_config_dialog.cancelled.connect(_on_gateway_config_cancelled)

	# Connect totem signals
	if _totem_interactable != null:
		@warning_ignore("return_value_discarded")
		_totem_interactable.interacted.connect(_on_totem_interacted)
	if _totem_ui != null:
		@warning_ignore("return_value_discarded")
		_totem_ui.gateway_clear_requested.connect(_on_gateway_clear_requested)

	# Connect travel confirmation dialog signals
	if _travel_confirm_dialog != null:
		@warning_ignore("return_value_discarded")
		_travel_confirm_dialog.confirmed.connect(_on_travel_confirm_confirmed)
		@warning_ignore("return_value_discarded")
		_travel_confirm_dialog.cancelled.connect(_on_travel_confirm_cancelled)

	# Connect lobby manager signals for gateway validation
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_data_received.connect(_on_lobby_data_received)

	# Spawn gateways
	_spawn_gateways()

	# Generate static field elements (obstacles, ground color) - all peers do this
	_generate_field_visuals()

	# Check if we're restoring a cached field
	var is_restoring: bool = MapManager.get_pending_field_restoration() != null

	# Spawn players and generate/restore items (server-only)
	if multiplayer.has_multiplayer_peer():
		print("Field: Has multiplayer peer, is_server: %s" % multiplayer.is_server())
		if multiplayer.is_server():
			_spawn_all_connected_players()
			if is_restoring:
				# Restore cached state instead of generating new items
				_restore_cached_state()
			else:
				_generate_field_items()
		_update_status()
	else:
		print("Field: No multiplayer peer!")


func _read_field_metadata() -> void:
	## Read field generation parameters from lobby metadata.
	var lobby_id: int = LobbyManager.current_lobby_id
	if lobby_id <= 0:
		return

	var seed_str: String = LobbyManager.get_lobby_metadata(lobby_id, "generation_seed")
	if not seed_str.is_empty():
		_generation_seed = seed_str.to_int()

	var origin_str: String = LobbyManager.get_lobby_metadata(lobby_id, "origin_lobby_id")
	if not origin_str.is_empty():
		_origin_lobby_id = origin_str.to_int()

	var gateway_str: String = LobbyManager.get_lobby_metadata(lobby_id, "origin_gateway")
	if not gateway_str.is_empty():
		_origin_gateway = gateway_str.to_int()

	_origin_map_name = LobbyManager.get_lobby_metadata(lobby_id, "origin_map_name")

	var pearl_str: String = LobbyManager.get_lobby_metadata(lobby_id, "pearl_type")
	if not pearl_str.is_empty():
		_pearl_type = StringName(pearl_str)

	print("Field: seed=%d, origin=%d, gateway=%d, origin_name=%s, pearl=%s" % [
		_generation_seed, _origin_lobby_id, _origin_gateway, _origin_map_name, _pearl_type
	])


func _generate_field_visuals() -> void:
	## All peers: Generate static field visuals (obstacles, ground color) based on seed and pearl type.
	## These are deterministic and don't need networking since all peers have the seed.
	if _generation_seed == 0:
		print("Field: No seed available, using default visuals")
		return

	print("Field: Generating visuals with seed %d, pearl %s..." % [_generation_seed, _pearl_type])

	# Create the procedural generator with seed and pearl type
	_field_generator = ProceduralFieldGenerator.new(_generation_seed, _pearl_type)

	# Apply ground color based on pearl type theme
	_apply_ground_color()

	# Spawn obstacles with themed colors (static, deterministic)
	_spawn_obstacles()

	print("Field: Generated %s-themed field visuals" % [_pearl_type if _pearl_type != &"" else "default"])


func _generate_field_items() -> void:
	## Server-only: Spawn items based on procedural generation.
	if not multiplayer.is_server():
		return

	if _field_generator == null:
		_field_generator = ProceduralFieldGenerator.new(_generation_seed, _pearl_type)

	# Spawn items (networked via MultiplayerSpawner)
	var items: Array[Dictionary] = _field_generator.generate_items()
	for item_data: Dictionary in items:
		var item_id: StringName = item_data.get("item_id", &"")
		var pos: Vector3 = item_data.get("position", Vector3.ZERO)
		var quantity: int = item_data.get("quantity", 1)
		if item_id != &"":
			_spawn_item_at(item_id, pos, quantity)

	print("Field: Spawned %d items" % items.size())


func _apply_ground_color() -> void:
	## Apply the theme-based ground color to the terrain.
	## All peers call this with the same seed, so no networking needed.
	if _field_generator == null or _ground_mesh == null:
		return

	var ground_color: Color = _field_generator.get_ground_color()
	var material: StandardMaterial3D = _ground_mesh.get_surface_override_material(0)

	if material == null:
		material = StandardMaterial3D.new()
		_ground_mesh.set_surface_override_material(0, material)

	material.albedo_color = ground_color


func _spawn_obstacles() -> void:
	## All peers: Spawn obstacles based on procedural generation.
	## Deterministic from seed, so all peers generate the same obstacles.
	if _field_generator == null or _obstacles_container == null:
		return

	var obstacles: Array[Dictionary] = _field_generator.generate_obstacles()

	for obstacle_data: Dictionary in obstacles:
		var obstacle: FieldObstacle = OBSTACLE_SCENE.instantiate()
		var pos: Vector3 = obstacle_data.get("position", Vector3.ZERO)
		var obstacle_type: String = obstacle_data.get("type", "rock")
		var scale_factor: float = obstacle_data.get("scale", 1.0)
		var rotation_y: float = obstacle_data.get("rotation_y", 0.0)

		# Get themed color for this obstacle type
		var themed_color: Color = _field_generator.get_obstacle_color(obstacle_type)

		obstacle.position = pos
		obstacle.setup(obstacle_type, scale_factor, rotation_y, themed_color)
		_obstacles_container.add_child(obstacle)

	print("Field: Spawned %d obstacles" % obstacles.size())


func _spawn_all_connected_players() -> void:
	print("Field: Spawning all connected players...")

	@warning_ignore("return_value_discarded")
	_player_spawner.spawn(1)

	var peers: PackedInt32Array = multiplayer.get_peers()
	for peer_id in peers:
		if peer_id != 1:
			print("Field: Spawning existing peer: %d" % peer_id)
			@warning_ignore("return_value_discarded")
			_player_spawner.spawn(peer_id)


func _is_player_spawned(peer_id: int) -> bool:
	return _players_container.has_node(str(peer_id))


func _spawn_player(peer_id: int) -> Node:
	var role: String = "Server" if multiplayer.is_server() else "Client"
	print("Field: _spawn_player() called for peer %d (I am %s)" % [peer_id, role])

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	if player == null:
		push_error("Field: Failed to instantiate player scene for peer %d" % peer_id)
		return null

	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	var spawn_point := _get_next_spawn_point()
	player.position = spawn_point

	print("Field: Created player node '%s' at position %s" % [player.name, spawn_point])
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
	_status_label.text = "Field - %s - %d player(s)" % [role, player_count]


func _on_player_spawned(node: Node) -> void:
	print("Field: Player spawned: %s" % node.name)
	_update_status()


func _on_player_added(_node: Node) -> void:
	_update_status()


func _on_player_removed(_node: Node) -> void:
	call_deferred("_update_status")


func _on_peer_connected(peer_id: int) -> void:
	print("Field: Peer connected: %d" % peer_id)
	if multiplayer.is_server() and not _is_player_spawned(peer_id):
		@warning_ignore("return_value_discarded")
		_player_spawner.spawn(peer_id)
	_update_status()


func _on_peer_disconnected(peer_id: int) -> void:
	print("Field: Peer disconnected: %d" % peer_id)
	var player_node := _players_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
	_update_status()


func _on_server_disconnected() -> void:
	print("Field: Server disconnected")
	_return_to_menu()


func _on_leave_button_pressed() -> void:
	_return_to_menu()


func _return_to_menu() -> void:
	NetworkManager.disconnect_peer()
	LobbyManager.leave_lobby()
	@warning_ignore("return_value_discarded")
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _exit_tree() -> void:
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
		push_error("Field: Invalid item spawn data")
		return null

	var spawn_data: Dictionary = data
	var item_id: StringName = _get_spawn_item_id(spawn_data)
	var pos: Vector3 = spawn_data.get("position", Vector3.ZERO)
	var quantity: int = spawn_data.get("quantity", 1)

	var item_data: ItemData = InventoryManager.get_item_data(item_id)
	if item_data == null or item_data.world_scene == null:
		push_error("Field: Unknown item or no world scene: %s" % item_id)
		return null

	var world_item: WorldItem = item_data.world_scene.instantiate()
	if world_item == null:
		push_error("Field: Failed to instantiate world item: %s" % item_id)
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
	var world_item: WorldItem = get_node_or_null(item_path)

	if world_item == null:
		print("Field: Pickup request failed - item not found: %s" % item_path)
		return

	var player_node: Node3D = _players_container.get_node_or_null(str(peer_id))
	if player_node == null:
		print("Field: Pickup request failed - player not found: %d" % peer_id)
		return

	var distance: float = player_node.global_position.distance_to(world_item.global_position)
	if distance > PICKUP_RANGE:
		print("Field: Pickup request failed - player too far: %.1f > %.1f" % [distance, PICKUP_RANGE])
		return

	var item_id: StringName = world_item.item_id
	var quantity: int = world_item.quantity

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
		print("Field: Picked up %d %s, %d overflow" % [quantity - overflow, item_id, overflow])
		if multiplayer.is_server():
			_process_drop(1, str(item_id), overflow)
		else:
			_request_drop.rpc_id(1, str(item_id), overflow)
	else:
		print("Field: Picked up %d %s" % [quantity, item_id])


@rpc("any_peer", "call_remote", "reliable")
func _request_drop(item_id_str: String, quantity: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_process_drop(sender_id, item_id_str, quantity)


func _process_drop(peer_id: int, item_id_str: String, quantity: int) -> void:
	var player_node: Node3D = _players_container.get_node_or_null(str(peer_id))

	if player_node == null:
		print("Field: Drop request failed - player not found: %d" % peer_id)
		return

	var drop_pos: Vector3 = player_node.global_position
	var forward: Vector3 = -player_node.global_transform.basis.z
	drop_pos += forward * 1.0
	drop_pos.y = 0.0

	var item_id: StringName = StringName(item_id_str)
	_spawn_item_at(item_id, drop_pos, quantity)
	print("Field: Dropped %d %s at %s" % [quantity, item_id, drop_pos])


func _on_drop_requested(item_id: StringName, quantity: int) -> void:
	if multiplayer.is_server():
		_process_drop(1, str(item_id), quantity)
	else:
		_request_drop.rpc_id(1, str(item_id), quantity)


func _on_inventory_full() -> void:
	if _toast_ui != null:
		_toast_ui.show_toast("Inventory Full")


# =============================================================================
# Gateway System
# =============================================================================

func _spawn_gateways() -> void:
	## Spawn the 4 gateways at the edges of the map.
	## One gateway (based on origin_gateway) will be the return path.
	_gateways.clear()

	# Determine which gateway is the return path
	# If origin_gateway is 0 (North), our South gateway (2) leads back
	var return_gateway_id: int = (_origin_gateway + 2) % 4

	for i in range(4):
		var gateway: Gateway = GATEWAY_SCENE.instantiate()
		gateway.gateway_id = i
		gateway.position = GATEWAY_POSITIONS[i]
		gateway.rotation_degrees.y = GATEWAY_ROTATIONS[i]

		# Set up the origin gateway (return path)
		if i == return_gateway_id and _origin_lobby_id > 0:
			gateway.is_origin_gateway = true
			var return_name: String = _origin_map_name if not _origin_map_name.is_empty() else "Origin"
			gateway.set_link(_origin_lobby_id, return_name)

		# Connect signals
		@warning_ignore("return_value_discarded")
		gateway.travel_requested.connect(_on_gateway_travel_requested.bind(gateway))
		@warning_ignore("return_value_discarded")
		gateway.travel_create_requested.connect(_on_gateway_travel_create_requested.bind(gateway))
		@warning_ignore("return_value_discarded")
		gateway.configure_requested.connect(_on_gateway_configure_requested.bind(gateway))

		_gateways_container.add_child(gateway)
		_gateways.append(gateway)

	print("Field: Spawned %d gateways (return gateway: %d)" % [_gateways.size(), return_gateway_id])


func _on_gateway_travel_requested(player: Node3D, destination_lobby_id: int, gateway: Gateway) -> void:
	## Handle travel through a linked gateway.
	if player == null or not player.is_multiplayer_authority():
		return

	print("Field: Travel requested to lobby %d via %s gateway" % [
		destination_lobby_id, gateway.get_direction_name()
	])

	# For origin gateways returning to our own town, skip validation but show confirmation.
	# The town lobby may not exist anymore (host left to create the field),
	# but MapManager.travel_to_town() handles re-hosting our own town.
	if gateway.is_origin_gateway and MapManager.is_own_town_lobby(destination_lobby_id):
		print("Field: Origin gateway to own town - showing confirmation")
		_pending_travel_lobby_id = destination_lobby_id
		_pending_travel_is_town = true
		var destination_name: String = gateway.linked_map_name
		_travel_confirm_dialog.show_dialog(destination_name, destination_lobby_id)
		return

	# For non-origin gateways, validate the destination lobby still exists
	_pending_travel_gateway = gateway
	LobbyManager.request_lobby_data(destination_lobby_id)


func _on_gateway_configure_requested(player: Node3D, gateway: Gateway) -> void:
	## Handle gateway configuration request.
	## In fields, any player can configure non-origin gateways.
	if player == null or not player.is_multiplayer_authority():
		return

	if gateway.is_origin_gateway:
		if _toast_ui != null:
			_toast_ui.show_toast("Cannot reconfigure the return gateway")
		return

	print("Field: Configure requested for %s gateway" % gateway.get_direction_name())
	_pending_gateway_config = gateway
	_gateway_config_dialog.show_for_gateway(gateway.gateway_id, gateway.get_direction_name())


func _on_gateway_configured(generation_seed: int, field_name: String, pearl_type: StringName) -> void:
	## Handle gateway configuration from dialog. Just stores config, no travel.
	if _pending_gateway_config == null:
		return

	var gateway: Gateway = _pending_gateway_config
	_pending_gateway_config = null

	print("Field: Configured %s gateway for field '%s' (seed %d, pearl %s)" % [
		gateway.get_direction_name(), field_name, generation_seed, pearl_type
	])

	# Configure the gateway with seed, name, and pearl type (no lobby created yet)
	gateway.set_config(generation_seed, field_name, pearl_type)


func _on_gateway_travel_create_requested(
	player: Node3D, generation_seed: int, field_name: String, pearl_type: StringName, gateway: Gateway
) -> void:
	## Handle travel when field needs to be created first.
	## In fields, any player can create new fields.
	if player == null or not player.is_multiplayer_authority():
		return

	print("Field: Creating and traveling to field '%s' (seed %d, pearl %s) via %s gateway" % [
		field_name, generation_seed, pearl_type, gateway.get_direction_name()
	])

	# Cache current field state before leaving
	_cache_field_state()

	# Create the field and travel
	MapManager.create_field(
		generation_seed,
		LobbyManager.current_lobby_id,
		gateway.gateway_id,
		"Field %d" % _generation_seed,  # Pass current field name as origin
		pearl_type
	)


func _on_gateway_config_cancelled() -> void:
	_pending_gateway_config = null


func _on_lobby_data_received(lobby_id: int, exists: bool) -> void:
	## Handle response from gateway destination validation.
	if _pending_travel_gateway == null:
		return

	# Only process if this is the lobby we're waiting for
	if _pending_travel_gateway.linked_lobby_id != lobby_id:
		return

	var gateway: Gateway = _pending_travel_gateway
	_pending_travel_gateway = null

	if exists:
		# Lobby exists - show travel confirmation
		print("Field: Destination lobby %d validated, showing confirmation" % lobby_id)
		_pending_travel_lobby_id = lobby_id
		_pending_travel_is_town = gateway.is_origin_gateway
		var destination_name: String = gateway.linked_map_name
		_travel_confirm_dialog.show_dialog(destination_name, lobby_id)
	else:
		# Lobby no longer exists - check if we have cached state to restore
		if MapManager.has_cached_field(lobby_id):
			print("Field: Can restore cached field %d, showing confirmation" % lobby_id)
			_pending_travel_lobby_id = lobby_id
			_pending_travel_is_town = false  # Cached fields are always fields
			var destination_name: String = gateway.linked_map_name
			_travel_confirm_dialog.show_dialog(destination_name, lobby_id)
		else:
			# No cached state - clear the stale link
			print("Field: Destination lobby %d no longer exists, clearing stale link" % lobby_id)
			_clear_stale_gateway_link(gateway)


func _clear_stale_gateway_link(gateway: Gateway) -> void:
	## Clear a gateway link that points to a non-existent lobby.
	gateway.clear_link()

	# Show feedback to player
	if _toast_ui != null:
		_toast_ui.show_toast("Destination no longer exists")


# =============================================================================
# Field State Caching
# =============================================================================

func _cache_field_state() -> void:
	## Serialize and cache the current field state before leaving.
	if not multiplayer.is_server():
		return

	var items: Array[Dictionary] = _serialize_items()
	var gateways: Array[Dictionary] = _serialize_gateways()

	MapManager.cache_current_field(items, gateways)
	print("Field: Cached state (%d items, %d gateways)" % [items.size(), gateways.size()])


func _serialize_items() -> Array[Dictionary]:
	## Serialize all world items currently in the field.
	var items: Array[Dictionary] = []

	# Get the node where items are spawned (spawn_path target of ItemSpawner)
	var spawn_target: Node = _item_spawner.get_node(_item_spawner.spawn_path)
	if spawn_target == null:
		push_warning("Field: Could not find item spawn target")
		return items

	for child: Node in spawn_target.get_children():
		if child is WorldItem:
			var item: WorldItem = child as WorldItem
			items.append({
				"item_id": str(item.item_id),
				"position": item.global_position,
				"quantity": item.quantity
			})

	return items


func _serialize_gateways() -> Array[Dictionary]:
	## Serialize all gateway configurations.
	var gateways_data: Array[Dictionary] = []

	for gateway: Gateway in _gateways:
		gateways_data.append({
			"id": gateway.gateway_id,
			"linked_lobby_id": gateway.linked_lobby_id,
			"linked_map_name": gateway.linked_map_name,
			"generation_seed": gateway.generation_seed,
			"pearl_type": String(gateway.pearl_type),
			"is_origin_gateway": gateway.is_origin_gateway
		})

	return gateways_data


func _restore_cached_state() -> void:
	## Restore field state from cache if available.
	var state: FieldStateCache.FieldState = MapManager.get_pending_field_restoration()
	if state == null:
		return

	print("Field: Restoring cached state...")

	# Restore items (server only)
	if multiplayer.is_server():
		for item_data: Dictionary in state.items:
			var item_id_str: Variant = item_data.get("item_id", "")
			var item_id: StringName = StringName(str(item_id_str))
			var pos: Vector3 = item_data.get("position", Vector3.ZERO)
			var quantity: int = item_data.get("quantity", 1)
			if item_id != &"":
				_spawn_item_at(item_id, pos, quantity)
		print("Field: Restored %d items" % state.items.size())

	# Restore gateway configurations
	for gateway_data: Dictionary in state.gateways:
		var gw_id: int = gateway_data.get("id", -1)
		if gw_id >= 0 and gw_id < _gateways.size():
			var gateway: Gateway = _gateways[gw_id]
			var is_origin: bool = gateway_data.get("is_origin_gateway", false)

			# Don't override origin gateway (it's set up in _spawn_gateways)
			if not is_origin and not gateway.is_origin_gateway:
				var linked_id: int = gateway_data.get("linked_lobby_id", 0)
				var linked_name: String = gateway_data.get("linked_map_name", "")
				var gen_seed: int = gateway_data.get("generation_seed", 0)
				var pearl_str: String = gateway_data.get("pearl_type", "")
				var pearl: StringName = StringName(pearl_str) if not pearl_str.is_empty() else &""

				if linked_id > 0:
					# Check if the linked lobby was remapped to a new ID
					var current_id: int = MapManager.get_current_field_lobby_id(linked_id)
					gateway.set_link(current_id, linked_name)
					gateway.pearl_type = pearl
				elif gen_seed > 0:
					gateway.set_config(gen_seed, linked_name, pearl)

	print("Field: Restored gateway configurations")

	# Clear the restoration state
	MapManager.clear_field_restoration()


# =============================================================================
# Totem Interaction
# =============================================================================

func _on_totem_interacted(player: Node3D) -> void:
	## Handle player interacting with the field totem.
	if player == null or not player.is_multiplayer_authority():
		return

	var field_name: String = "Field %d" % _generation_seed
	var player_count: int = _players_container.get_child_count()
	var host_name: String = SteamManager.get_steam_username() if multiplayer.is_server() else "Unknown"
	var is_host: bool = multiplayer.is_server()

	# Pass false for is_host to hide edit button (field names aren't editable)
	_totem_ui.show_ui(field_name, player_count, host_name, false)

	# Pass gateway data to the UI (host can clear non-origin gateways)
	var gateway_data: Array[Dictionary] = _get_gateway_data_for_ui()
	_totem_ui.set_gateway_data(gateway_data, is_host)


func _get_gateway_data_for_ui() -> Array[Dictionary]:
	## Collect gateway connection data for the totem UI.
	var data: Array[Dictionary] = []
	for gateway: Gateway in _gateways:
		data.append({
			"has_link": gateway.has_link(),
			"linked_map_name": gateway.linked_map_name,
			"is_origin": gateway.is_origin_gateway
		})
	return data


func _on_gateway_clear_requested(gateway_id: int) -> void:
	## Handle request to clear a gateway connection.
	if not multiplayer.is_server():
		return

	if gateway_id < 0 or gateway_id >= _gateways.size():
		return

	var gateway: Gateway = _gateways[gateway_id]
	if gateway.is_origin_gateway:
		return  # Cannot clear origin gateway

	print("Field: Clearing gateway %d (%s)" % [gateway_id, gateway.get_direction_name()])
	gateway.clear_link()

	# Refresh the totem UI
	var gateway_data: Array[Dictionary] = _get_gateway_data_for_ui()
	_totem_ui.set_gateway_data(gateway_data, true)


# =============================================================================
# Travel Confirmation
# =============================================================================

func _on_travel_confirm_confirmed() -> void:
	## Handle player confirming travel via confirmation dialog.
	var lobby_id: int = _travel_confirm_dialog.get_destination_lobby_id()
	var is_town: bool = _pending_travel_is_town

	_pending_travel_lobby_id = 0
	_pending_travel_is_town = false
	_pending_travel_gateway = null

	if lobby_id > 0:
		print("Field: Travel confirmed to lobby %d" % lobby_id)
		# Cache current field state before leaving
		_cache_field_state()
		if is_town:
			MapManager.travel_to_town(lobby_id)
		elif MapManager.has_cached_field(lobby_id):
			# Restore cached field
			@warning_ignore("return_value_discarded")
			MapManager.restore_cached_field(lobby_id)
		else:
			MapManager.travel_to_field(lobby_id)


func _on_travel_confirm_cancelled() -> void:
	## Handle player cancelling travel via confirmation dialog.
	_pending_travel_lobby_id = 0
	_pending_travel_is_town = false
	_pending_travel_gateway = null
	print("Field: Travel cancelled")
