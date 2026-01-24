extends Node3D
## Town map scene - persistent player-owned map.
## Saves state to Steam Cloud and has configurable gateway links.

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


@onready var _spawn_points: Node3D = $SpawnPoints
@onready var _players_container: Node3D = $Players
@onready var _player_spawner: MultiplayerSpawner = $MultiplayerSpawner
@onready var _item_spawner: MultiplayerSpawner = $ItemSpawner
@onready var _status_label: Label = $UI/StatusLabel
@onready var _inventory_ui: InventoryUI = $UI/InventoryUI
@onready var _toast_ui: ToastUI = $UI/ToastUI
@onready var _gateways_container: Node3D = $Gateways
@onready var _gateway_config_dialog: GatewayConfigDialog = $UI/GatewayConfigDialog
@onready var _town_name_dialog: TownNameDialog = $UI/TownNameDialog
@onready var _totem_ui: TotemUI = $UI/TotemUI
@onready var _totem_interactable: Interactable = $Environment/Totem/Interactable
@onready var _host_travel_warning: HostTravelWarning = $UI/HostTravelWarning
@onready var _travel_confirm_dialog: TravelConfirmDialog = $UI/TravelConfirmDialog

var _spawn_index: int = 0
var _gateways: Array[Gateway] = []
var _pending_gateway_config: Gateway = null
var _pending_travel_gateway: Gateway = null
var _pending_travel_lobby_id: int = 0
var _pending_create_seed: int = 0
var _pending_create_pearl_type: StringName = &""
var _town_storage: TownCloudStorage = null
var _is_loading_complete: bool = false


func _ready() -> void:
	var role: String = "Server" if multiplayer.is_server() else "Client"
	var peer_id: int = multiplayer.get_unique_id()
	print("Town: _ready() called - Role: %s, PeerID: %d" % [role, peer_id])

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

	# Connect town name dialog signals
	if _town_name_dialog != null:
		@warning_ignore("return_value_discarded")
		_town_name_dialog.name_confirmed.connect(_on_town_name_confirmed)

	# Connect totem signals
	if _totem_interactable != null:
		@warning_ignore("return_value_discarded")
		_totem_interactable.interacted.connect(_on_totem_interacted)
	if _totem_ui != null:
		@warning_ignore("return_value_discarded")
		_totem_ui.edit_name_requested.connect(_on_totem_edit_name_requested)
		@warning_ignore("return_value_discarded")
		_totem_ui.gateway_clear_requested.connect(_on_gateway_clear_requested)

	# Connect host travel warning signals
	if _host_travel_warning != null:
		@warning_ignore("return_value_discarded")
		_host_travel_warning.confirmed.connect(_on_host_travel_confirmed)
		@warning_ignore("return_value_discarded")
		_host_travel_warning.cancelled.connect(_on_host_travel_cancelled)

	# Connect travel confirmation dialog signals
	if _travel_confirm_dialog != null:
		@warning_ignore("return_value_discarded")
		_travel_confirm_dialog.confirmed.connect(_on_travel_confirm_confirmed)
		@warning_ignore("return_value_discarded")
		_travel_confirm_dialog.cancelled.connect(_on_travel_confirm_cancelled)

	# Connect lobby manager signals for gateway validation
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_data_received.connect(_on_lobby_data_received)

	# Spawn gateways (links will be restored after storage loads)
	_spawn_gateways()

	# Spawn players
	if multiplayer.has_multiplayer_peer():
		print("Town: Has multiplayer peer, is_server: %s" % multiplayer.is_server())
		if multiplayer.is_server():
			_spawn_all_connected_players()
			# Initialize and load town storage
			_init_town_storage()
		else:
			# Clients don't load storage, just mark as ready
			_is_loading_complete = true
		_update_status()
	else:
		print("Town: No multiplayer peer!")


func _spawn_all_connected_players() -> void:
	print("Town: Spawning all connected players...")

	@warning_ignore("return_value_discarded")
	_player_spawner.spawn(1)

	var peers: PackedInt32Array = multiplayer.get_peers()
	for peer_id in peers:
		if peer_id != 1:
			print("Town: Spawning existing peer: %d" % peer_id)
			@warning_ignore("return_value_discarded")
			_player_spawner.spawn(peer_id)


func _is_player_spawned(peer_id: int) -> bool:
	return _players_container.has_node(str(peer_id))


func _spawn_player(peer_id: int) -> Node:
	var role: String = "Server" if multiplayer.is_server() else "Client"
	print("Town: _spawn_player() called for peer %d (I am %s)" % [peer_id, role])

	var player: CharacterBody3D = PLAYER_SCENE.instantiate()
	if player == null:
		push_error("Town: Failed to instantiate player scene for peer %d" % peer_id)
		return null

	player.name = str(peer_id)
	player.set_multiplayer_authority(peer_id)

	var spawn_point := _get_next_spawn_point()
	player.position = spawn_point

	print("Town: Created player node '%s' at position %s" % [player.name, spawn_point])
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
	var town_name: String = get_town_name()
	if town_name.is_empty():
		town_name = "Town"
	_status_label.text = "%s - %s - %d player(s)" % [town_name, role, player_count]


func _on_player_spawned(node: Node) -> void:
	print("Town: Player spawned: %s" % node.name)
	_update_status()


func _on_player_added(_node: Node) -> void:
	_update_status()


func _on_player_removed(_node: Node) -> void:
	call_deferred("_update_status")


func _on_peer_connected(peer_id: int) -> void:
	print("Town: Peer connected: %d" % peer_id)
	if multiplayer.is_server() and not _is_player_spawned(peer_id):
		@warning_ignore("return_value_discarded")
		_player_spawner.spawn(peer_id)
	_update_status()


func _on_peer_disconnected(peer_id: int) -> void:
	print("Town: Peer disconnected: %d" % peer_id)
	var player_node := _players_container.get_node_or_null(str(peer_id))
	if player_node:
		player_node.queue_free()
	_update_status()


func _on_server_disconnected() -> void:
	print("Town: Server disconnected")
	_return_to_menu()


func _on_leave_button_pressed() -> void:
	_return_to_menu()


func _return_to_menu() -> void:
	NetworkManager.disconnect_peer()
	LobbyManager.leave_lobby()
	@warning_ignore("return_value_discarded")
	get_tree().change_scene_to_file("res://scenes/main_menu/main_menu.tscn")


func _exit_tree() -> void:
	# Flush pending saves before exiting
	if _town_storage != null:
		_town_storage.flush()

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
# Item Spawning (copied from world.gd)
# =============================================================================

func _spawn_initial_items() -> void:
	## Spawn one of each pearl type in a new town.
	if not multiplayer.is_server():
		return

	# Spawn one of each pearl type at different positions
	var pearl_spawns: Array[Dictionary] = [
		{"id": &"flame_pearl", "pos": Vector3(2, 0, 2)},
		{"id": &"air_pearl", "pos": Vector3(-2, 0, 2)},
		{"id": &"life_pearl", "pos": Vector3(2, 0, -2)},
		{"id": &"water_pearl", "pos": Vector3(-2, 0, -2)},
	]

	for spawn: Dictionary in pearl_spawns:
		_spawn_item_at(spawn["id"], spawn["pos"], 1)

	print("Town: Spawned %d initial pearls (one of each type)" % pearl_spawns.size())


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
		push_error("Town: Invalid item spawn data")
		return null

	var spawn_data: Dictionary = data
	var item_id: StringName = _get_spawn_item_id(spawn_data)
	var pos: Vector3 = spawn_data.get("position", Vector3.ZERO)
	var quantity: int = spawn_data.get("quantity", 1)

	var item_data: ItemData = InventoryManager.get_item_data(item_id)
	if item_data == null or item_data.world_scene == null:
		push_error("Town: Unknown item or no world scene: %s" % item_id)
		return null

	var world_item: WorldItem = item_data.world_scene.instantiate()
	if world_item == null:
		push_error("Town: Failed to instantiate world item: %s" % item_id)
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
		print("Town: Pickup request failed - item not found: %s" % item_path)
		return

	var player_node: Node3D = _players_container.get_node_or_null(str(peer_id))
	if player_node == null:
		print("Town: Pickup request failed - player not found: %d" % peer_id)
		return

	var distance: float = player_node.global_position.distance_to(world_item.global_position)
	if distance > PICKUP_RANGE:
		print("Town: Pickup request failed - player too far: %.1f > %.1f" % [distance, PICKUP_RANGE])
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
		print("Town: Picked up %d %s, %d overflow" % [quantity - overflow, item_id, overflow])
		if multiplayer.is_server():
			_process_drop(1, str(item_id), overflow)
		else:
			_request_drop.rpc_id(1, str(item_id), overflow)
	else:
		print("Town: Picked up %d %s" % [quantity, item_id])


@rpc("any_peer", "call_remote", "reliable")
func _request_drop(item_id_str: String, quantity: int) -> void:
	if not multiplayer.is_server():
		return

	var sender_id: int = multiplayer.get_remote_sender_id()
	_process_drop(sender_id, item_id_str, quantity)


func _process_drop(peer_id: int, item_id_str: String, quantity: int) -> void:
	var player_node: Node3D = _players_container.get_node_or_null(str(peer_id))

	if player_node == null:
		print("Town: Drop request failed - player not found: %d" % peer_id)
		return

	var drop_pos: Vector3 = player_node.global_position
	var forward: Vector3 = -player_node.global_transform.basis.z
	drop_pos += forward * 1.0
	drop_pos.y = 0.0

	var item_id: StringName = StringName(item_id_str)
	_spawn_item_at(item_id, drop_pos, quantity)
	print("Town: Dropped %d %s at %s" % [quantity, item_id, drop_pos])


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
	_gateways.clear()

	for i in range(4):
		var gateway: Gateway = GATEWAY_SCENE.instantiate()
		gateway.gateway_id = i
		gateway.position = GATEWAY_POSITIONS[i]
		gateway.rotation_degrees.y = GATEWAY_ROTATIONS[i]

		# Connect signals
		@warning_ignore("return_value_discarded")
		gateway.travel_requested.connect(_on_gateway_travel_requested.bind(gateway))
		@warning_ignore("return_value_discarded")
		gateway.travel_create_requested.connect(_on_gateway_travel_create_requested.bind(gateway))
		@warning_ignore("return_value_discarded")
		gateway.configure_requested.connect(_on_gateway_configure_requested.bind(gateway))

		_gateways_container.add_child(gateway)
		_gateways.append(gateway)

	print("Town: Spawned %d gateways" % _gateways.size())


func _on_gateway_travel_requested(player: Node3D, destination_lobby_id: int, gateway: Gateway) -> void:
	## Handle travel through a linked gateway.
	if player == null or not player.is_multiplayer_authority():
		return

	print("Town: Travel requested to lobby %d via %s gateway" % [
		destination_lobby_id, gateway.get_direction_name()
	])

	# Validate the destination lobby still exists before traveling
	_pending_travel_gateway = gateway
	LobbyManager.request_lobby_data(destination_lobby_id)


func _on_gateway_configure_requested(player: Node3D, gateway: Gateway) -> void:
	## Handle gateway configuration request.
	if player == null or not player.is_multiplayer_authority():
		return

	# Only host can configure town gateways
	if not multiplayer.is_server():
		if _toast_ui != null:
			_toast_ui.show_toast("Only the host can configure gateways")
		return

	print("Town: Configure requested for %s gateway" % gateway.get_direction_name())
	_pending_gateway_config = gateway
	_gateway_config_dialog.show_for_gateway(gateway.gateway_id, gateway.get_direction_name())


func _on_gateway_configured(generation_seed: int, field_name: String, pearl_type: StringName) -> void:
	## Handle gateway configuration from dialog. Just stores config, no travel.
	if _pending_gateway_config == null:
		return

	var gateway: Gateway = _pending_gateway_config
	_pending_gateway_config = null

	print("Town: Configured %s gateway for field '%s' (seed %d, pearl %s)" % [
		gateway.get_direction_name(), field_name, generation_seed, pearl_type
	])

	# Configure the gateway with seed, name, and pearl type (no lobby created yet)
	gateway.set_config(generation_seed, field_name, pearl_type)

	# Save gateway config to persistent storage
	if multiplayer.is_server() and _town_storage != null:
		_town_storage.set_gateway_config(
			gateway.gateway_id, generation_seed, field_name, pearl_type
		)


func _on_gateway_travel_create_requested(
	player: Node3D, generation_seed: int, field_name: String, pearl_type: StringName, gateway: Gateway
) -> void:
	## Handle travel when field needs to be created first.
	if player == null or not player.is_multiplayer_authority():
		return

	print("Town: Travel + create requested for field '%s' (seed %d, pearl %s) via %s gateway" % [
		field_name, generation_seed, pearl_type, gateway.get_direction_name()
	])

	# Store which gateway triggered this for updating after validation
	_pending_travel_gateway = gateway

	# Show host warning if applicable
	if multiplayer.is_server():
		_pending_travel_lobby_id = -1  # Special value indicating "create new field"
		_pending_create_seed = generation_seed
		_pending_create_pearl_type = pearl_type
		_host_travel_warning.show_warning()
	else:
		# Non-host can only travel to existing fields, not create them
		if _toast_ui != null:
			_toast_ui.show_toast("Only the host can create new fields")


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
		# Lobby exists - check if we're the host and need to show a warning
		if multiplayer.is_server():
			print("Town: Host attempting to leave, showing warning")
			_pending_travel_lobby_id = lobby_id
			_host_travel_warning.show_warning()
		else:
			# Client needs travel confirmation
			print("Town: Showing travel confirmation for lobby %d" % lobby_id)
			_pending_travel_lobby_id = lobby_id
			var destination_name: String = gateway.linked_map_name
			_travel_confirm_dialog.show_dialog(destination_name, lobby_id)
	else:
		# Lobby no longer exists - check if we have cached state to restore
		if MapManager.has_cached_field(lobby_id):
			print("Town: Restoring cached field %d" % lobby_id)
			# Only host can restore fields (need to become the host of the restored field)
			if multiplayer.is_server():
				_pending_travel_lobby_id = lobby_id
				_host_travel_warning.show_warning()
			else:
				if _toast_ui != null:
					_toast_ui.show_toast("Field is not currently hosted")
		else:
			# No cached state - clear the stale link
			print("Town: Destination lobby %d no longer exists, clearing stale link" % lobby_id)
			_clear_stale_gateway_link(gateway)


func _on_host_travel_confirmed() -> void:
	## Handle host confirming they want to leave the town.
	var gateway: Gateway = _pending_travel_gateway
	_pending_travel_gateway = null

	if _pending_travel_lobby_id == -1 and _pending_create_seed > 0:
		# Create new field and travel
		var field_seed: int = _pending_create_seed
		var pearl_type: StringName = _pending_create_pearl_type
		_pending_create_seed = 0
		_pending_create_pearl_type = &""
		_pending_travel_lobby_id = 0

		print("Town: Host confirmed field creation with seed %d, pearl %s" % [field_seed, pearl_type])
		MapManager.create_field(
			field_seed,
			LobbyManager.current_lobby_id,
			gateway.gateway_id if gateway != null else 0,
			get_town_name(),
			pearl_type
		)
	elif _pending_travel_lobby_id > 0:
		var lobby_id: int = _pending_travel_lobby_id
		_pending_travel_lobby_id = 0
		_pending_create_seed = 0
		_pending_create_pearl_type = &""

		# Check if this is a cached field that needs restoration
		if MapManager.has_cached_field(lobby_id):
			print("Town: Host confirmed restoration of cached field %d" % lobby_id)
			@warning_ignore("return_value_discarded")
			MapManager.restore_cached_field(lobby_id)
		else:
			# Travel to existing field
			print("Town: Host confirmed travel to lobby %d" % lobby_id)
			MapManager.travel_to_field(lobby_id)
	else:
		_pending_travel_lobby_id = 0
		_pending_create_seed = 0
		_pending_create_pearl_type = &""


func _on_host_travel_cancelled() -> void:
	## Handle host cancelling travel.
	_pending_travel_lobby_id = 0
	_pending_create_seed = 0
	_pending_create_pearl_type = &""
	_pending_travel_gateway = null
	print("Town: Host cancelled travel")


func _on_travel_confirm_confirmed() -> void:
	## Handle player confirming travel via confirmation dialog.
	var lobby_id: int = _travel_confirm_dialog.get_destination_lobby_id()
	_pending_travel_lobby_id = 0
	_pending_travel_gateway = null

	if lobby_id > 0:
		print("Town: Travel confirmed to lobby %d" % lobby_id)
		MapManager.travel_to_field(lobby_id)


func _on_travel_confirm_cancelled() -> void:
	## Handle player cancelling travel via confirmation dialog.
	_pending_travel_lobby_id = 0
	_pending_travel_gateway = null
	print("Town: Travel cancelled")


func _clear_stale_gateway_link(gateway: Gateway) -> void:
	## Clear a gateway link that points to a non-existent lobby.
	gateway.clear_link()

	# Update persistent storage if host
	if multiplayer.is_server() and _town_storage != null:
		_town_storage.set_gateway_link(gateway.gateway_id, 0, "")

	# Show feedback to player
	if _toast_ui != null:
		_toast_ui.show_toast("Destination no longer exists")


# =============================================================================
# Town State Persistence
# =============================================================================

func _init_town_storage() -> void:
	## Initialize town storage and begin loading (host only).
	_town_storage = TownCloudStorage.new()
	_town_storage.setup(self)
	@warning_ignore("return_value_discarded")
	_town_storage.load_completed.connect(_on_town_load_completed)
	_town_storage.load_state()


func _on_town_load_completed(success: bool) -> void:
	if not success:
		push_warning("Town: Failed to load town state")

	if _town_storage.is_new_town():
		print("Town: New town - showing name dialog")
		_town_name_dialog.show_for_new_town()
	else:
		print("Town: Loaded existing town: %s" % _town_storage.get_town_name())
		_finish_town_loading()


func _on_town_name_confirmed(town_name: String) -> void:
	print("Town: Name set to: %s" % town_name)
	_town_storage.set_town_name(town_name)

	# Update lobby metadata with town name
	@warning_ignore("return_value_discarded")
	LobbyManager.set_lobby_metadata("server_name", town_name)

	# If we're editing (not first-time creation), update UI and status
	if _is_loading_complete:
		_totem_ui.update_town_name(town_name)
		_update_status()
	else:
		_finish_town_loading()


func _finish_town_loading() -> void:
	## Called after town state is loaded and name is set.
	_is_loading_complete = true

	# Restore gateway links from saved state
	_restore_gateway_links()

	# Spawn initial items if this is a new town
	if _town_storage.is_new_town():
		_spawn_initial_items()

	# Update lobby metadata with current town name
	var town_name: String = _town_storage.get_town_name()
	if not town_name.is_empty():
		@warning_ignore("return_value_discarded")
		LobbyManager.set_lobby_metadata("server_name", town_name)

	_update_status()


func _restore_gateway_links() -> void:
	## Restore gateway links and configurations from saved town state.
	if _town_storage == null:
		return

	for i: int in range(_gateways.size()):
		var gateway_data: Dictionary = _town_storage.get_gateway(i)
		var lobby_id: int = gateway_data.get("linked_lobby_id", 0)
		var map_name: String = gateway_data.get("linked_map_name", "")
		var field_seed: int = gateway_data.get("generation_seed", 0)
		var pearl_type_str: String = gateway_data.get("pearl_type", "")
		var pearl_type: StringName = StringName(pearl_type_str) if not pearl_type_str.is_empty() else &""

		if lobby_id > 0:
			# Has a created field
			_gateways[i].set_link(lobby_id, map_name)
			_gateways[i].generation_seed = field_seed
			_gateways[i].pearl_type = pearl_type
			print("Town: Restored gateway %d link to %s (lobby %d, pearl %s)" % [i, map_name, lobby_id, pearl_type])
		elif field_seed > 0 and not map_name.is_empty():
			# Configured but field not created yet
			_gateways[i].set_config(field_seed, map_name, pearl_type)
			print("Town: Restored gateway %d config for %s (seed %d, pearl %s)" % [i, map_name, field_seed, pearl_type])


func _save_gateway_link(gateway_id: int, lobby_id: int, map_name: String) -> void:
	## Save a gateway link to persistent storage.
	if _town_storage == null:
		return

	_town_storage.set_gateway_link(gateway_id, lobby_id, map_name)


func get_town_name() -> String:
	## Get the current town name.
	if _town_storage == null:
		return ""
	return _town_storage.get_town_name()


# =============================================================================
# Totem Interaction
# =============================================================================

func _on_totem_interacted(player: Node3D) -> void:
	## Handle player interacting with the town totem.
	if player == null or not player.is_multiplayer_authority():
		return

	var town_name: String = get_town_name()
	var player_count: int = _players_container.get_child_count()
	var host_name: String = SteamManager.get_steam_username()
	var is_host: bool = multiplayer.is_server()

	_totem_ui.show_ui(town_name, player_count, host_name, is_host)

	# Pass gateway data to the UI
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

	print("Town: Clearing gateway %d (%s)" % [gateway_id, gateway.get_direction_name()])
	gateway.clear_link()

	# Update storage
	if _town_storage != null:
		_town_storage.clear_gateway_link(gateway_id)

	# Refresh the totem UI
	var gateway_data: Array[Dictionary] = _get_gateway_data_for_ui()
	_totem_ui.set_gateway_data(gateway_data, true)


func _on_totem_edit_name_requested() -> void:
	## Handle request to edit town name from totem UI.
	if not multiplayer.is_server():
		return

	# Hide totem UI and show name dialog
	_totem_ui.visible = false
	_town_name_dialog.show_for_edit(get_town_name())
