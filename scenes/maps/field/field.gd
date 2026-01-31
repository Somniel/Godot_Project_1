extends "res://scenes/maps/map_base.gd"
## Field map scene - temporary procedurally generated map.
## Does not persist to Steam Cloud. Exists only while hosted or linked.

const OBSTACLE_SCENE: PackedScene = preload("res://scenes/world/obstacle/obstacle.tscn")

@onready var _obstacles_container: Node3D = $Obstacles
@onready var _ground_mesh: MeshInstance3D = $Environment/Ground/MeshInstance3D

var _pending_travel_is_town: bool = false
var _pending_travel_owner_steam_id: int = 0
var _field_generator: ProceduralFieldGenerator = null
var _town_gateway_provider: PlayerTownGatewayProvider = null
var _town_linker: FieldTownLinker = FieldTownLinker.new()
var _cloud_persistence: FieldCloudPersistence = FieldCloudPersistence.new()

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

## Steam ID of the town owner that created this field (stable identifier)
var _origin_owner_steam_id: int = 0

## Current state version for version sync (incremented on each state change)
var _current_state_version: int = 0

## Peer ID we requested field state from (0 = none pending)
var _pending_state_request_peer: int = 0

## Pearl type awaiting server confirmation before consuming (client only)
var _pending_pearl_consumption: StringName = &""
## Gateway ID for which we're awaiting config confirmation (client only)
var _pending_config_gateway_id: int = -1


func _ready() -> void:
	var role: String = "Server" if multiplayer.is_server() else "Client"
	var peer_id: int = multiplayer.get_unique_id()
	print("Field: _ready() called - Role: %s, PeerID: %d" % [role, peer_id])

	# Read field metadata
	_read_field_metadata()

	# Connect shared signals (network, spawners, inventory, gateway dialog, etc.)
	_connect_shared_signals()

	# Connect field-specific signals
	_connect_field_signals()

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
				# Priority 1: Restore from session cache (multiplayer scenario)
				_restore_cached_state()
			elif _load_from_town_cloud():
				# Priority 2: Restore from town's Steam Cloud (game restart scenario)
				# _load_from_town_cloud() already spawned items and configured gateways
				print("Field: Restored state from town cloud storage")
			else:
				# Priority 3: Generate fresh items (first-time creation)
				_generate_field_items()
			# Restore field→town links from town cloud gateway data.
			# Town gateways store which field gateway they link to; this creates
			# the reverse links on unconfigured field gateways.
			@warning_ignore("return_value_discarded")
			_town_linker.restore_town_gateway_links(
				_gateways, _generation_seed, _origin_map_name
			)
			# Update all town gateways that link to this field with the new lobby ID
			_town_linker.update_all_town_gateways_for_field(
				_gateways, _generation_seed, _origin_map_name
			)
		_update_status()
	else:
		print("Field: No multiplayer peer!")


func _connect_field_signals() -> void:
	## Connect field-specific signals not handled by MapBase.
	if _gateway_config_dialog != null:
		@warning_ignore("return_value_discarded")
		_gateway_config_dialog.town_link_requested.connect(_on_town_link_requested)

	# Client gateway config requests (server only)
	if multiplayer.is_server():
		@warning_ignore("return_value_discarded")
		NetworkManager.client_gateway_config_requested.connect(
			_on_client_gateway_config_requested
		)

	# Client-only signals
	if not multiplayer.is_server():
		@warning_ignore("return_value_discarded")
		NetworkManager.field_cache_received.connect(_on_field_cache_received)
		@warning_ignore("return_value_discarded")
		NetworkManager.gateway_config_confirmed.connect(_on_gateway_config_confirmed)
		@warning_ignore("return_value_discarded")
		NetworkManager.gateway_config_rejected.connect(_on_gateway_config_rejected)

	# Version exchange signals for state versioning
	@warning_ignore("return_value_discarded")
	NetworkManager.field_version_received.connect(_on_field_version_received)
	@warning_ignore("return_value_discarded")
	NetworkManager.field_state_requested.connect(_on_field_state_requested)
	@warning_ignore("return_value_discarded")
	NetworkManager.field_state_received.connect(_on_field_state_received)


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

	var owner_str: String = LobbyManager.get_lobby_metadata(lobby_id, "origin_owner_steam_id")
	if not owner_str.is_empty():
		_origin_owner_steam_id = owner_str.to_int()

	var origin_raw: String = LobbyManager.get_lobby_metadata(lobby_id, "origin_lobby_id")
	print("Field: seed=%d, origin=%d (raw='%s'), gateway=%d, origin_name=%s, pearl=%s, owner=%d" % [
		_generation_seed, _origin_lobby_id, origin_raw, _origin_gateway,
		_origin_map_name, _pearl_type, _origin_owner_steam_id
	])


func _is_own_field() -> bool:
	## Check if this field was created from the local player's own town.
	## Uses stable Steam ID comparison instead of ephemeral lobby ID matching.
	if _origin_owner_steam_id > 0:
		return _origin_owner_steam_id == SteamManager.get_steam_id()
	# Fallback for fields created before origin_owner_steam_id was stored
	return MapManager.is_own_town_lobby(_origin_lobby_id)


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

	print("Field: Generated %s-themed field visuals" % [_pearl_type if _pearl_type != &"" else &"default"])


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


# =============================================================================
# MapBase Virtual Overrides
# =============================================================================

func _get_map_type_name() -> String:
	return "Field"


func _update_status() -> void:
	if not is_inside_tree() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	var player_count: int = _players_container.get_child_count()
	var role: String = "Host" if multiplayer.is_server() else "Client"
	_status_label.text = "Field - %s - %d player(s)" % [role, player_count]


func _on_peer_connected(peer_id: int) -> void:
	super(peer_id)
	if multiplayer.is_server():
		# Sync all gateway states to the new peer
		_sync_all_gateways_to_peer(peer_id)
		# Sync field cache to the new peer
		_sync_field_cache_to_peer(peer_id)
		# Send our state version to the peer for version comparison
		NetworkManager.send_field_version_to_peer(
			peer_id, _generation_seed, _current_state_version,
			SteamManager.get_steam_id()
		)
	else:
		# Client: Send our version to the server when we connect
		NetworkManager.broadcast_field_version(
			_generation_seed, _current_state_version,
			SteamManager.get_steam_id()
		)


func _on_peer_disconnected(peer_id: int) -> void:
	super(peer_id)
	if peer_id == _pending_state_request_peer:
		_pending_state_request_peer = 0


func _on_travel_confirm_cancelled() -> void:
	super()
	_pending_travel_is_town = false
	_pending_travel_owner_steam_id = 0


func _exit_tree() -> void:
	_disconnect_shared_signals()
	_disconnect_field_signals()


func _disconnect_field_signals() -> void:
	## Disconnect field-specific signals.
	if _gateway_config_dialog and _gateway_config_dialog.town_link_requested.is_connected(
		_on_town_link_requested
	):
		_gateway_config_dialog.town_link_requested.disconnect(_on_town_link_requested)
	if NetworkManager.client_gateway_config_requested.is_connected(
		_on_client_gateway_config_requested
	):
		NetworkManager.client_gateway_config_requested.disconnect(
			_on_client_gateway_config_requested
		)
	if NetworkManager.field_cache_received.is_connected(_on_field_cache_received):
		NetworkManager.field_cache_received.disconnect(_on_field_cache_received)
	if NetworkManager.gateway_config_confirmed.is_connected(_on_gateway_config_confirmed):
		NetworkManager.gateway_config_confirmed.disconnect(_on_gateway_config_confirmed)
	if NetworkManager.gateway_config_rejected.is_connected(_on_gateway_config_rejected):
		NetworkManager.gateway_config_rejected.disconnect(_on_gateway_config_rejected)
	if NetworkManager.field_version_received.is_connected(_on_field_version_received):
		NetworkManager.field_version_received.disconnect(_on_field_version_received)
	if NetworkManager.field_state_requested.is_connected(_on_field_state_requested):
		NetworkManager.field_state_requested.disconnect(_on_field_state_requested)
	if NetworkManager.field_state_received.is_connected(_on_field_state_received):
		NetworkManager.field_state_received.disconnect(_on_field_state_received)


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

	# Get effective origin lobby ID (may have changed if town was re-hosted)
	var effective_origin_lobby: int = _origin_lobby_id
	if _origin_lobby_id > 0 and _is_own_field():
		var current_town_id: int = MapManager.get_own_town_lobby_id()
		if current_town_id > 0 and current_town_id != _origin_lobby_id:
			print("Field: Remapping origin lobby %d -> %d (town was re-hosted)" % [
				_origin_lobby_id, current_town_id
			])
			effective_origin_lobby = current_town_id

	# Get the origin town owner's Steam ID (for town link)
	var origin_owner_steam_id: int = _origin_owner_steam_id
	# Fallback: if origin is our own town, use our Steam ID
	if origin_owner_steam_id == 0 and _is_own_field():
		origin_owner_steam_id = SteamManager.get_steam_id()

	for i in range(4):
		var gateway: Gateway = GATEWAY_SCENE.instantiate()
		gateway.gateway_id = i
		gateway.position = GATEWAY_POSITIONS[i]
		gateway.rotation_degrees.y = GATEWAY_ROTATIONS[i]

		# Set up the origin gateway (return path to town)
		if i == return_gateway_id and effective_origin_lobby > 0:
			gateway.is_origin_gateway = true
			var return_name: String = _origin_map_name if not _origin_map_name.is_empty() else "Origin"
			# Use set_town_link since origin is always a town
			# Pass _origin_gateway as the target so we know which town gateway to return to
			gateway.set_town_link(origin_owner_steam_id, effective_origin_lobby, return_name, _origin_gateway)
			print("Field: Origin gateway %d set up: lobby=%d, target_gw=%d, owner=%d" % [
				i, effective_origin_lobby, _origin_gateway, origin_owner_steam_id
			])

		# Connect signals
		@warning_ignore("return_value_discarded")
		gateway.travel_requested.connect(_on_gateway_travel_requested.bind(gateway))
		@warning_ignore("return_value_discarded")
		gateway.travel_create_requested.connect(_on_gateway_travel_create_requested.bind(gateway))
		@warning_ignore("return_value_discarded")
		gateway.configure_requested.connect(_on_gateway_configure_requested.bind(gateway))

		_gateways_container.add_child(gateway)
		_gateways.append(gateway)

	print("Field: Spawned %d gateways (return gateway: %d, origin_owner: %d)" % [
		_gateways.size(), return_gateway_id, origin_owner_steam_id
	])


func _on_gateway_travel_requested(player: Node3D, destination_lobby_id: int, gateway: Gateway) -> void:
	## Handle travel through a linked gateway.
	if player == null or not player.is_multiplayer_authority():
		return

	print("Field: Travel requested to lobby %d via %s gateway" % [
		destination_lobby_id, gateway.get_direction_name()
	])

	# For town links, check ownership using stable Steam ID
	# Also fall back to _is_own_field() in case the gateway's Steam ID was
	# lost during JSON serialization (large int precision)
	if gateway.is_town_link():
		var is_own: bool = gateway.linked_owner_steam_id == SteamManager.get_steam_id() \
			or _is_own_field()
		if is_own:
			# Own town - skip lobby validation (we'll re-host it)
			# Use our actual Steam ID in case the gateway's value was corrupted
			print("Field: Gateway to own town - showing confirmation")
			_pending_travel_gateway = gateway
			_pending_travel_lobby_id = destination_lobby_id
			_pending_travel_is_town = true
			_pending_travel_owner_steam_id = SteamManager.get_steam_id()
			var destination_name: String = gateway.linked_map_name
			_travel_confirm_dialog.show_dialog(destination_name, destination_lobby_id)
			return
		else:
			# Other player's town - validate the lobby still exists
			print("Field: Gateway to other player's town - validating lobby")
			_pending_travel_gateway = gateway
			_pending_travel_is_town = true
			_pending_travel_owner_steam_id = gateway.linked_owner_steam_id
			LobbyManager.request_lobby_data(destination_lobby_id)
			return

	# For field links, validate the destination lobby still exists
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

	# Load player's town gateways before showing dialog
	_town_gateway_provider = PlayerTownGatewayProvider.new()
	@warning_ignore("return_value_discarded")
	_town_gateway_provider.gateways_loaded.connect(_on_town_gateways_loaded)
	_town_gateway_provider.load_gateways()


func _on_town_gateways_loaded(gateways: Array) -> void:
	## Handle town gateways loaded - now show the config dialog.
	## Note: Parameter is untyped Array because signal parameters lose type info at runtime.
	if _pending_gateway_config == null:
		return

	# Only show town link option if:
	# 1. Player is the host (only host can modify shared field gateway state)
	# 2. This field originated from the player's own town
	# This prevents confusion and ensures data integrity.
	var is_host: bool = multiplayer.is_server()
	var is_own_field: bool = _is_own_field()
	var show_town_link: bool = is_host and is_own_field

	var town_gateways_to_show: Array[Dictionary] = []
	if show_town_link:
		for gw: Variant in gateways:
			if gw is Dictionary:
				@warning_ignore("unsafe_cast")
				town_gateways_to_show.append(gw as Dictionary)

	print("Field: Town link check - is_host=%s, origin_lobby=%d, is_own_field=%s, show=%s, gateways=%d" % [
		is_host, _origin_lobby_id, is_own_field, show_town_link, gateways.size()
	])

	# Show the extended dialog with town link option (only if host on own field)
	_gateway_config_dialog.show_for_field_gateway(
		_pending_gateway_config.gateway_id,
		_pending_gateway_config.get_direction_name(),
		town_gateways_to_show
	)


func _on_gateway_configured(generation_seed: int, field_name: String, pearl_type: StringName) -> void:
	## Handle gateway configuration from dialog. Just stores config, no travel.
	if _pending_gateway_config == null:
		return

	var gateway: Gateway = _pending_gateway_config
	_pending_gateway_config = null

	print("Field: Configured %s gateway for field '%s' (seed %d, pearl %s)" % [
		gateway.get_direction_name(), field_name, generation_seed, pearl_type
	])

	if multiplayer.is_server():
		# Server: consume pearl immediately, apply config, and broadcast
		if not GatewayConfigDialog.consume_pearl_from_inventory(pearl_type):
			push_warning("Field: Server failed to consume pearl")
			return
		gateway.set_config(generation_seed, field_name, pearl_type)
		NetworkManager.broadcast_gateway_state(
			gateway.gateway_id, 0, field_name, generation_seed, pearl_type, -1
		)
	else:
		# Client: store pending pearl and send request to server.
		# Pearl is consumed only after server confirms.
		_pending_pearl_consumption = pearl_type
		_pending_config_gateway_id = gateway.gateway_id
		NetworkManager.send_gateway_config_request(
			gateway.gateway_id, generation_seed, field_name, pearl_type
		)


func _on_client_gateway_config_requested(peer_id: int, gateway_id: int, generation_seed: int,
										 field_name: String, pearl_type: String) -> void:
	## Server handler for client gateway configuration requests.
	if not multiplayer.is_server():
		return

	if gateway_id < 0 or gateway_id >= _gateways.size():
		push_warning("Field: Invalid gateway_id %d from peer %d" % [gateway_id, peer_id])
		NetworkManager.send_gateway_config_rejection(
			peer_id, gateway_id, "Invalid gateway"
		)
		return

	var gateway: Gateway = _gateways[gateway_id]

	# Don't allow configuring origin gateway
	if gateway.is_origin_gateway:
		push_warning("Field: Peer %d tried to configure origin gateway" % peer_id)
		NetworkManager.send_gateway_config_rejection(
			peer_id, gateway_id, "Cannot configure origin gateway"
		)
		return

	# Don't allow reconfiguring already-linked gateways
	if gateway.has_link():
		push_warning("Field: Peer %d tried to reconfigure linked gateway %d" % [peer_id, gateway_id])
		NetworkManager.send_gateway_config_rejection(
			peer_id, gateway_id, "Gateway already configured"
		)
		return

	print("Field: Server applying gateway config from peer %d for gateway %d" % [peer_id, gateway_id])

	var pearl_sn: StringName = StringName(pearl_type) if not pearl_type.is_empty() else &""

	# Apply the configuration
	gateway.set_config(generation_seed, field_name, pearl_sn)

	# Broadcast to all clients (including the requester)
	NetworkManager.broadcast_gateway_state(
		gateway_id, 0, field_name, generation_seed, pearl_sn, -1
	)

	# Confirm to the requesting client so they can consume their pearl
	NetworkManager.send_gateway_config_confirmation(
		peer_id, gateway_id, generation_seed, field_name, pearl_sn
	)


func _on_gateway_config_confirmed(
	gateway_id: int, _confirmed_seed: int, _field_name: String,
	pearl_type: String
) -> void:
	## Client handler: server confirmed our gateway config, consume the pearl.
	if gateway_id != _pending_config_gateway_id:
		return

	var pearl_sn: StringName = StringName(pearl_type)
	if _pending_pearl_consumption != &"" and pearl_sn == _pending_pearl_consumption:
		if not GatewayConfigDialog.consume_pearl_from_inventory(pearl_sn):
			push_warning("Field: Failed to consume pearl after server confirmation")

	_pending_pearl_consumption = &""
	_pending_config_gateway_id = -1


func _on_gateway_config_rejected(gateway_id: int, reason: String) -> void:
	## Client handler: server rejected our gateway config, pearl is preserved.
	if gateway_id != _pending_config_gateway_id:
		return

	print("Field: Gateway config rejected by server: %s" % reason)
	if _toast_ui != null:
		_toast_ui.show_toast("Gateway configuration failed: %s" % reason)

	_pending_pearl_consumption = &""
	_pending_config_gateway_id = -1


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

	# Set travel source so destination knows where we came from
	MapManager.set_travel_source(
		LobbyManager.current_lobby_id, gateway.gateway_id, -1, "field"
	)

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


func _on_town_link_requested(town_gateway_id: int) -> void:
	## Handle request to link this field gateway to player's town gateway.
	if _pending_gateway_config == null:
		return

	var field_gateway: Gateway = _pending_gateway_config
	_pending_gateway_config = null

	# SECURITY CHECK 1: Only the host can create town links (involves broadcasting shared state)
	if not multiplayer.is_server():
		if _toast_ui != null:
			_toast_ui.show_toast("Only the host can link to town")
		print("Field: Rejected town link - not the host")
		return

	# SECURITY CHECK 2: Only allow linking when this field originated from the player's OWN town.
	# This prevents players from accidentally linking to someone else's town when visiting
	# their field. The origin_lobby_id is the town that created this field, which may not
	# be the current player's town.
	if not _is_own_field():
		if _toast_ui != null:
			_toast_ui.show_toast("Can only link to town from your own field")
		print("Field: Rejected town link - origin is not player's own town")
		return

	print("Field: Linking gateway %d to town gateway %d" % [
		field_gateway.gateway_id, town_gateway_id
	])

	_create_town_link(field_gateway, town_gateway_id)


func _create_town_link(field_gateway: Gateway, town_gateway_id: int) -> void:
	## Create bidirectional link between field gateway and player's town gateway.
	## IMPORTANT: This should only be called after validating that origin is player's own town.

	# The origin is our own town (validated in _on_town_link_requested)
	var player_town_name: String = _origin_map_name if not _origin_map_name.is_empty() else "Town"

	# Double-check: ensure this is the player's own field
	if not _is_own_field():
		push_warning("Field: _create_town_link called but origin is not player's own town")
		if _toast_ui != null:
			_toast_ui.show_toast("Cannot link - not your town")
		return

	# Use current town lobby ID (may have changed from _origin_lobby_id after re-hosting)
	var owner_steam_id: int = SteamManager.get_steam_id()
	var current_town_lobby: int = MapManager.get_own_town_lobby_id()
	if current_town_lobby <= 0:
		current_town_lobby = _origin_lobby_id
	field_gateway.set_town_link(owner_steam_id, current_town_lobby, player_town_name, town_gateway_id)

	# Broadcast the gateway state change to all clients (including target gateway for travel)
	if multiplayer.is_server():
		NetworkManager.broadcast_gateway_state(
			field_gateway.gateway_id, current_town_lobby, player_town_name, 0, &"",
			town_gateway_id, "town", owner_steam_id
		)

	# Update player's town gateway in Steam Cloud to link back to this field
	# Pass the field gateway ID so the town gateway knows which field gateway to arrive at
	_town_linker.update_town_gateway_to_link_here(
		town_gateway_id, field_gateway.gateway_id, _generation_seed, _pearl_type
	)

	if _toast_ui != null:
		var dir_name: String = PlayerTownGatewayProvider.get_direction_name(town_gateway_id)
		_toast_ui.show_toast("Linked to your town's %s gateway" % dir_name)


func _sync_all_gateways_to_peer(peer_id: int) -> void:
	## Send all gateway states to a specific peer (called when they connect).
	if not multiplayer.is_server():
		return

	for gateway: Gateway in _gateways:
		# Convert link_type enum to string
		var link_type_str: String = "none"
		match gateway.link_type:
			Gateway.LinkType.FIELD:
				link_type_str = "field"
			Gateway.LinkType.TOWN:
				link_type_str = "town"

		NetworkManager.sync_gateway_state_to_peer(
			peer_id,
			gateway.gateway_id,
			gateway.linked_lobby_id,
			gateway.linked_map_name,
			gateway.generation_seed,
			gateway.pearl_type,
			gateway.linked_gateway_id,
			link_type_str,
			gateway.linked_owner_steam_id
		)


func _on_gateway_state_received(gateway_id: int, data: Dictionary) -> void:
	## Handle gateway state update from server (clients only).
	if multiplayer.is_server():
		return  # Server doesn't need to process its own broadcasts

	if gateway_id < 0 or gateway_id >= _gateways.size():
		return

	var gateway: Gateway = _gateways[gateway_id]

	# Don't override origin gateway state from sync
	if gateway.is_origin_gateway:
		return

	var lobby_id: int = data.get("linked_lobby_id", 0)
	var map_name: String = data.get("linked_map_name", "")
	var seed_val: int = data.get("generation_seed", 0)
	var pearl_str: String = data.get("pearl_type", "")
	var pearl_type: StringName = StringName(pearl_str) if not pearl_str.is_empty() else &""
	var linked_gw_id: int = data.get("linked_gateway_id", -1)
	var link_type_str: String = data.get("link_type", "none")
	var owner_steam_id: int = data.get("linked_owner_steam_id", 0)

	if link_type_str == "town" and owner_steam_id > 0:
		# Town link - use set_town_link
		gateway.set_town_link(owner_steam_id, lobby_id, map_name, linked_gw_id)
	elif link_type_str == "field" and (lobby_id > 0 or seed_val > 0):
		if lobby_id > 0:
			# Full field link exists
			gateway.set_link(lobby_id, map_name, linked_gw_id)
			gateway.generation_seed = seed_val
			gateway.pearl_type = pearl_type
		else:
			# Configured but not yet created
			gateway.set_config(seed_val, map_name, pearl_type)
	else:
		# Cleared or unknown type
		gateway.clear_link()

	print("Field: Received gateway %d sync from server (type=%s, lobby=%d, name=%s, target_gw=%d)" % [
		gateway_id, link_type_str, lobby_id, map_name, linked_gw_id
	])


func _sync_field_cache_to_peer(peer_id: int) -> void:
	## Send field cache to a specific peer (called when they connect).
	if not multiplayer.is_server():
		return

	var cache: FieldStateCache = MapManager.get_field_cache()
	if cache == null:
		return

	var entries: Array[Dictionary] = cache.serialize_all()
	if entries.is_empty():
		return

	NetworkManager.sync_field_cache_to_peer(peer_id, entries, {})


func _broadcast_field_cache() -> void:
	## Broadcast field cache to all connected clients (called before host leaves).
	if not multiplayer.is_server():
		return

	var cache: FieldStateCache = MapManager.get_field_cache()
	if cache == null:
		return

	var entries: Array[Dictionary] = cache.serialize_all()
	if entries.is_empty():
		return

	NetworkManager.broadcast_field_cache(entries, {})


func _on_field_cache_received(entries: Array, _remappings: Dictionary) -> void:
	## Handle field cache data received from server.
	if multiplayer.is_server():
		return  # Server doesn't need to receive its own broadcasts

	var cache: FieldStateCache = MapManager.get_field_cache()
	if cache == null:
		return

	cache.merge_entries(entries)
	print("Field: Merged field cache from server")


func _on_field_version_received(
	peer_id: int, generation_seed: int, version: int,
	modifier_steam_id: int
) -> void:
	## Handle version info received from a peer.
	## If their version is newer, request their full state.
	## On equal versions, higher modifier Steam ID wins (deterministic tiebreaker).
	if generation_seed != _generation_seed:
		return  # Not about this field

	print("Field: Received v%d from peer %d (our v%d)" % [
		version, peer_id, _current_state_version
	])

	var dominated: bool = false
	if version > _current_state_version:
		dominated = true
	elif version == _current_state_version and version > 0:
		# Tiebreaker: higher Steam ID wins
		if modifier_steam_id > SteamManager.get_steam_id():
			dominated = true
			print("Field: Equal version %d, peer wins tiebreak (%d > %d)" % [
				version, modifier_steam_id, SteamManager.get_steam_id()
			])

	if dominated:
		print("Field: Peer %d has authoritative version, requesting state..." % peer_id)
		_pending_state_request_peer = peer_id
		NetworkManager.request_field_state.rpc_id(peer_id, generation_seed)


func _on_field_state_requested(peer_id: int, generation_seed: int) -> void:
	## Handle request for our field state from a peer who has older version.
	if generation_seed != _generation_seed:
		return  # Not about this field

	print("Field: Peer %d requested our state (version %d)" % [peer_id, _current_state_version])

	# Serialize and send our current state
	var spawn_target: Node = _item_spawner.get_node(_item_spawner.spawn_path)
	var items: Array[Dictionary] = _cloud_persistence.serialize_items(spawn_target)
	var gateways: Array[Dictionary] = _cloud_persistence.serialize_gateways(_gateways)

	var state_data: Dictionary = {
		"generation_seed": _generation_seed,
		"state_version": _current_state_version,
		"last_modified_by": SteamManager.get_steam_id(),
		"origin_lobby_id": _origin_lobby_id,
		"origin_gateway": _origin_gateway,
		"origin_map_name": _origin_map_name,
		"pearl_type": String(_pearl_type),
		"items": items,
		"gateways": gateways
	}

	var state_json: String = JSON.stringify(state_data)
	NetworkManager.send_field_state_to_peer(peer_id, generation_seed, state_json)


func _on_field_state_received(
	sender_id: int, generation_seed: int, state_json: String
) -> void:
	## Handle full field state received from a peer with newer version.
	if generation_seed != _generation_seed:
		return  # Not about this field

	# Reject state from unexpected peers
	if _pending_state_request_peer != 0 and sender_id != _pending_state_request_peer:
		push_warning("Field: Rejected state from peer %d (expected %d)" % [
			sender_id, _pending_state_request_peer
		])
		return

	var parsed: Variant = JSON.parse_string(state_json)
	if not parsed is Dictionary:
		push_warning("Field: Failed to parse received field state")
		return

	@warning_ignore("unsafe_cast")
	var state_data: Dictionary = parsed as Dictionary
	var received_version: int = state_data.get("state_version", 0)
	var remote_modifier: int = state_data.get("last_modified_by", 0)

	if received_version < _current_state_version:
		print("Field: Ignoring older state v%d (our: v%d)" % [
			received_version, _current_state_version
		])
		return

	if received_version == _current_state_version:
		# Tiebreaker: higher Steam ID wins
		if remote_modifier <= SteamManager.get_steam_id():
			print("Field: Ignoring equal v%d state, we win tiebreak" % [
				received_version
			])
			return

	print("Field: Adopting newer state version %d from peer %d (was %d)" % [
		received_version, sender_id, _current_state_version
	])

	# Update our version and clear pending request
	_current_state_version = received_version
	_pending_state_request_peer = 0

	# Only server can actually update world state (spawn/despawn items)
	if multiplayer.is_server():
		# Clear existing items and respawn from received state
		_clear_all_items()

		var items_data: Variant = state_data.get("items", [])
		if items_data is Array:
			@warning_ignore("unsafe_cast")
			for item_data: Variant in (items_data as Array):
				if item_data is Dictionary:
					@warning_ignore("unsafe_cast")
					var item_dict: Dictionary = item_data as Dictionary
					var item_id_str: Variant = item_dict.get("item_id", "")
					var item_id: StringName = StringName(str(item_id_str))
					var pos: Vector3 = FieldCloudPersistence.parse_position(
						item_dict.get("position", null)
					)
					var quantity: int = item_dict.get("quantity", 1)
					if item_id != &"":
						_spawn_item_at(item_id, pos, quantity)

		# Update gateway configurations
		var gateways_data: Variant = state_data.get("gateways", [])
		if gateways_data is Array:
			@warning_ignore("unsafe_cast")
			_apply_gateway_state(gateways_data as Array)

		print("Field: Applied newer state from peer")


func _clear_all_items() -> void:
	## Remove all world items from the field (for state replacement).
	if not multiplayer.is_server():
		return

	var spawn_target: Node = _item_spawner.get_node(_item_spawner.spawn_path)
	if spawn_target == null:
		return

	for child: Node in spawn_target.get_children():
		if child is WorldItem:
			child.queue_free()


func _apply_gateway_state(gateways_data: Array) -> void:
	## Apply gateway configurations from serialized data.
	for gateway_data: Variant in gateways_data:
		if not gateway_data is Dictionary:
			continue

		@warning_ignore("unsafe_cast")
		var gw_dict: Dictionary = gateway_data as Dictionary
		var gw_id: int = gw_dict.get("id", -1)
		if gw_id < 0 or gw_id >= _gateways.size():
			continue

		var gateway: Gateway = _gateways[gw_id]
		var is_origin: bool = gw_dict.get("is_origin_gateway", false)

		# Don't override origin gateway
		if is_origin or gateway.is_origin_gateway:
			continue

		var linked_id: int = gw_dict.get("linked_lobby_id", 0)
		var linked_name: String = gw_dict.get("linked_map_name", "")
		var gen_seed: int = gw_dict.get("generation_seed", 0)
		var pearl_str: String = gw_dict.get("pearl_type", "")
		var pearl: StringName = StringName(pearl_str) if not pearl_str.is_empty() else &""
		var linked_gw_id: int = gw_dict.get("linked_gateway_id", -1)

		if linked_id > 0:
			gateway.set_link(linked_id, linked_name, linked_gw_id)
			gateway.pearl_type = pearl
		elif gen_seed > 0:
			gateway.set_config(gen_seed, linked_name, pearl)
		else:
			gateway.clear_link()


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
		if not _pending_travel_is_town:
			_pending_travel_is_town = gateway.is_town_link()
		var destination_name: String = gateway.linked_map_name
		_travel_confirm_dialog.show_dialog(destination_name, lobby_id)
	else:
		# Lobby no longer exists
		if gateway.is_town_link():
			# Town link - don't clear (owner_steam_id is stable), just show message
			print("Field: Town lobby %d not currently hosted" % lobby_id)
			_pending_travel_is_town = false
			_pending_travel_owner_steam_id = 0
			if _toast_ui != null:
				_toast_ui.show_toast("Town is not currently hosted")
		elif MapManager.has_cached_field(lobby_id):
			# Field link with cached state - offer to restore
			print("Field: Can restore cached field %d, showing confirmation" % lobby_id)
			_pending_travel_lobby_id = lobby_id
			_pending_travel_is_town = false
			var destination_name: String = gateway.linked_map_name
			_travel_confirm_dialog.show_dialog(destination_name, lobby_id)
		else:
			# Field link with no cached state - clear the stale link
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

	var spawn_target: Node = _item_spawner.get_node(_item_spawner.spawn_path)
	var items: Array[Dictionary] = _cloud_persistence.serialize_items(spawn_target)
	var gateways: Array[Dictionary] = _cloud_persistence.serialize_gateways(_gateways)

	# Increment state version
	_current_state_version += 1

	# Get modifier Steam ID (local player's Steam ID)
	var modifier_steam_id: int = SteamManager.get_steam_id()

	# Save to session cache (for multiplayer) - with version tracking
	MapManager.cache_current_field(items, gateways, modifier_steam_id)
	print("Field: Cached state v%d (%d items, %d gateways)" % [
		_current_state_version, items.size(), gateways.size()
	])

	# Also save to town's Steam Cloud if this is player's own linked field
	# This persists the state across game restarts
	if _is_own_field():
		@warning_ignore("return_value_discarded")
		_cloud_persistence.save_to_town_cloud(
			_generation_seed, _pearl_type, items, gateways
		)

	# Broadcast updated cache to all connected clients before leaving
	# This ensures other players can restore fields if they become host later
	_broadcast_field_cache()


func _load_from_town_cloud() -> bool:
	## Try to load field state from the player's town Steam Cloud storage.
	## Returns true if state was loaded and applied, false otherwise.
	if not _is_own_field():
		return false

	var field_dict: Variant = _cloud_persistence.load_from_town_cloud(_generation_seed)
	if field_dict == null:
		return false

	@warning_ignore("unsafe_cast")
	var data: Dictionary = field_dict as Dictionary

	print("Field: Loading state from town cloud (seed %d)..." % _generation_seed)

	# Restore items
	var items_variant: Variant = data.get("items", [])
	if items_variant is Array:
		@warning_ignore("unsafe_cast")
		var items: Array = items_variant as Array
		for item_data: Variant in items:
			if item_data is Dictionary:
				@warning_ignore("unsafe_cast")
				var item_dict: Dictionary = item_data as Dictionary
				var item_id_str: Variant = item_dict.get("item_id", "")
				var item_id: StringName = StringName(str(item_id_str))
				var pos: Vector3 = FieldCloudPersistence.parse_position(
					item_dict.get("position", null)
				)
				var quantity: int = item_dict.get("quantity", 1)
				if item_id != &"":
					_spawn_item_at(item_id, pos, quantity)
		print("Field: Restored %d items from town cloud" % items.size())

	# Restore gateway configurations
	var gateways_variant: Variant = data.get("gateways", [])
	if gateways_variant is Array:
		@warning_ignore("unsafe_cast")
		var gateways_data: Array = gateways_variant as Array
		_apply_gateway_configs_from_cloud(gateways_data)
		print("Field: Restored gateway configurations from town cloud")

	return true


func _apply_gateway_configs_from_cloud(gateways_data: Array) -> void:
	## Apply gateway configurations loaded from town cloud storage.
	## Handles lobby ID remapping and legacy data formats.
	for gateway_data: Variant in gateways_data:
		if not gateway_data is Dictionary:
			continue

		@warning_ignore("unsafe_cast")
		var gw_dict: Dictionary = gateway_data as Dictionary
		var gw_id: int = gw_dict.get("id", -1)
		if gw_id < 0 or gw_id >= _gateways.size():
			continue

		var gateway: Gateway = _gateways[gw_id]
		var is_origin: bool = gw_dict.get("is_origin_gateway", false)

		# Don't override origin gateway
		if is_origin or gateway.is_origin_gateway:
			continue

		var linked_id: int = gw_dict.get("linked_lobby_id", 0)
		var linked_name: String = gw_dict.get("linked_map_name", "")
		var gen_seed: int = gw_dict.get("generation_seed", 0)
		var pearl_str: String = gw_dict.get("pearl_type", "")
		var pearl: StringName = StringName(pearl_str) if not pearl_str.is_empty() else &""
		var linked_gw_id: int = gw_dict.get("linked_gateway_id", -1)
		var link_type_str: String = gw_dict.get("link_type", "none")
		var owner_steam_id: int = FieldCloudPersistence.parse_steam_id(
			gw_dict.get("linked_owner_steam_id", 0)
		)

		if link_type_str == "town":
			# Town link - always use current town lobby ID.
			# We're loading from our own town cloud, so all town
			# links in this data point to our town.
			var current_town_id: int = MapManager.get_own_town_lobby_id()
			var current_id: int = current_town_id if current_town_id > 0 else linked_id
			if current_id != linked_id and current_town_id > 0:
				print("Field: Remapping gateway %d town link %d -> %d (cloud)" % [
					gw_id, linked_id, current_id
				])
			if owner_steam_id == 0:
				owner_steam_id = SteamManager.get_steam_id()
			gateway.set_town_link(owner_steam_id, current_id, linked_name, linked_gw_id)
		elif link_type_str == "field" or (link_type_str == "none" and gen_seed > 0):
			# Field link - lobby IDs are stale after game restart
			# Keep seed for recreation but clear stale lobby ID
			if gen_seed > 0:
				gateway.set_config(gen_seed, linked_name, pearl)
				print("Field: Restored gateway %d as field config (seed %d)" % [
					gw_id, gen_seed
				])
			# else: seed 0 with field type = invalid, leave unconfigured
		elif linked_id > 0 and gen_seed == 0:
			# Legacy data: lobby ID but no link_type and no seed.
			# Likely a town link from before link_type was added.
			var current_town_id: int = MapManager.get_own_town_lobby_id()
			if current_town_id > 0:
				gateway.set_town_link(SteamManager.get_steam_id(),
					current_town_id, linked_name, linked_gw_id)
				print("Field: Converted legacy gateway %d to town link" % gw_id)
		elif linked_id > 0 and gen_seed > 0:
			# Legacy data: lobby ID with seed = field link, keep seed only
			gateway.set_config(gen_seed, linked_name, pearl)


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
			var pos: Vector3 = FieldCloudPersistence.parse_position(
				item_data.get("position", null)
			)
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
				var linked_gw_id: int = gateway_data.get("linked_gateway_id", -1)
				var link_type_str: String = gateway_data.get("link_type", "none")
				var owner_steam_id: int = FieldCloudPersistence.parse_steam_id(
					gateway_data.get("linked_owner_steam_id", 0)
				)

				if link_type_str == "town" and owner_steam_id > 0:
					# Town link - use current town lobby ID if it's our own
					var current_id: int = linked_id
					if owner_steam_id == SteamManager.get_steam_id():
						var current_town_id: int = MapManager.get_own_town_lobby_id()
						if current_town_id > 0:
							current_id = current_town_id
					gateway.set_town_link(owner_steam_id, current_id, linked_name, linked_gw_id)
				elif link_type_str == "field" and (linked_id > 0 or gen_seed > 0):
					if linked_id > 0:
						gateway.set_link(linked_id, linked_name, linked_gw_id)
						gateway.pearl_type = pearl
					else:
						gateway.set_config(gen_seed, linked_name, pearl)
				elif linked_id > 0:
					# Legacy data without link_type
					gateway.set_link(linked_id, linked_name, linked_gw_id)
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

	# Check if this gateway links to the player's own town (bidirectional link)
	# If so, we need to also clear the town gateway that points to this field
	var links_to_own_town: bool = gateway.is_town_link() and \
		(gateway.linked_owner_steam_id == SteamManager.get_steam_id() or _is_own_field())
	if links_to_own_town:
		_town_linker.clear_town_gateway_link(_generation_seed)

	gateway.clear_link()

	# Broadcast cleared gateway state to all clients
	NetworkManager.broadcast_gateway_state(gateway_id, 0, "", 0, &"", -1, "none", 0)

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
	var owner_steam_id: int = _pending_travel_owner_steam_id

	# Capture gateway info before clearing pending state
	var travel_gateway_id: int = -1
	var target_gateway_id: int = -1
	if _pending_travel_gateway != null:
		travel_gateway_id = _pending_travel_gateway.gateway_id
		target_gateway_id = _pending_travel_gateway.linked_gateway_id

	_pending_travel_lobby_id = 0
	_pending_travel_is_town = false
	_pending_travel_owner_steam_id = 0
	_pending_travel_gateway = null

	if lobby_id > 0 or (is_town and owner_steam_id > 0):
		var link_type: String = "town" if is_town else "field"
		print("Field: Travel confirmed (type=%s, lobby=%d, gateway=%d, target=%d)" % [
			link_type, lobby_id, travel_gateway_id, target_gateway_id
		])

		# Set travel source so destination knows where we came from
		MapManager.set_travel_source(
			LobbyManager.current_lobby_id, travel_gateway_id, target_gateway_id,
			link_type, owner_steam_id
		)

		# Cache current field state before leaving
		_cache_field_state()
		if is_town:
			MapManager.travel_to_player_town(owner_steam_id)
		elif MapManager.has_cached_field(lobby_id):
			@warning_ignore("return_value_discarded")
			MapManager.restore_cached_field(lobby_id)
		else:
			MapManager.travel_to_field(lobby_id)
