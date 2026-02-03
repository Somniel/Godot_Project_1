extends "res://scenes/maps/map_base.gd"
## Town map scene - persistent player-owned map.
## Saves state to Steam Cloud and has configurable gateway links.

@onready var _town_name_dialog: TownNameDialog = $UI/TownNameDialog
@onready var _host_travel_warning: HostTravelWarning = $UI/HostTravelWarning

var _pending_create_seed: int = 0
var _pending_create_pearl_type: StringName = &""
var _town_storage: TownCloudStorage = null
var _is_loading_complete: bool = false
## Tracks gateways with pending client field creations to prevent duplicates
var _pending_gateway_creations: Dictionary = {}  # gateway_id -> true


func _ready() -> void:
	var role: String = "Server" if multiplayer.is_server() else "Client"
	var peer_id: int = multiplayer.get_unique_id()
	print("Town: _ready() called - Role: %s, PeerID: %d" % [role, peer_id])

	# Connect shared signals (network, spawners, inventory, gateway dialog, etc.)
	_connect_shared_signals()

	# Connect town-specific signals
	_connect_town_signals()

	# Spawn gateways (links will be restored after storage loads)
	_spawn_gateways()

	# Spawn players
	if multiplayer.has_multiplayer_peer():
		print("Town: Has multiplayer peer, is_server: %s" % multiplayer.is_server())
		if multiplayer.is_server():
			# Initialize and load town storage BEFORE spawning
			# This ensures gateway links are available for spawn position calculation
			_init_town_storage()
			_spawn_all_connected_players()
		else:
			# Clients don't load storage, just mark as ready
			_is_loading_complete = true
		_update_status()
	else:
		print("Town: No multiplayer peer!")


func _connect_town_signals() -> void:
	## Connect town-specific signals not handled by MapBase.
	if _town_name_dialog != null:
		@warning_ignore("return_value_discarded")
		_town_name_dialog.name_confirmed.connect(_on_town_name_confirmed)

	if _totem_ui != null:
		@warning_ignore("return_value_discarded")
		_totem_ui.edit_name_requested.connect(_on_totem_edit_name_requested)

	if _host_travel_warning != null:
		@warning_ignore("return_value_discarded")
		_host_travel_warning.confirmed.connect(_on_host_travel_confirmed)
		@warning_ignore("return_value_discarded")
		_host_travel_warning.cancelled.connect(_on_host_travel_cancelled)

	# Server-only signals
	if multiplayer.is_server():
		@warning_ignore("return_value_discarded")
		NetworkManager.field_travel_requested.connect(
			_on_field_travel_requested
		)
		@warning_ignore("return_value_discarded")
		NetworkManager.field_state_returned.connect(
			_on_field_state_returned
		)

	# Client-only signals
	if not multiplayer.is_server():
		@warning_ignore("return_value_discarded")
		NetworkManager.field_cache_received.connect(_on_field_cache_received)
		@warning_ignore("return_value_discarded")
		NetworkManager.field_travel_approved.connect(
			_on_field_travel_approved
		)
		@warning_ignore("return_value_discarded")
		NetworkManager.field_state_return_requested.connect(
			_on_field_state_return_requested
		)


# =============================================================================
# MapBase Virtual Overrides
# =============================================================================

func _get_map_type_name() -> String:
	return "Town"


func _get_arrival_gateway_id() -> int:
	## Town-specific: also checks storage when gateways aren't configured yet.
	var result: int = super()
	if result >= 0:
		return result

	# If base class didn't find it, check storage directly
	var source_lobby: int = MapManager.get_source_lobby_id()
	if source_lobby <= 0:
		return -1

	if _town_storage != null:
		for i: int in range(4):
			var gateway_data: Dictionary = _town_storage.get_gateway(i)
			var lobby_id_value: Variant = gateway_data.get("linked_lobby_id", "0")
			var lobby_id: int = 0
			if lobby_id_value is String:
				@warning_ignore("unsafe_cast")
				lobby_id = (lobby_id_value as String).to_int()
			elif lobby_id_value is int or lobby_id_value is float:
				# Type-narrowed Variant; int() cast is safe after is-check
				@warning_ignore("unsafe_call_argument")
				lobby_id = int(lobby_id_value)
			if lobby_id == source_lobby:
				print("Town: Found gateway %d in storage linking to source lobby %d" % [
					i, source_lobby
				])
				return i

	return -1


func _update_status() -> void:
	if not is_inside_tree() or multiplayer == null or not multiplayer.has_multiplayer_peer():
		return
	var player_count: int = _players_container.get_child_count()
	var role: String = "Host" if multiplayer.is_server() else "Client"
	var town_name: String = get_town_name()
	if town_name.is_empty():
		town_name = "Town"
	_status_label.text = "%s - %s - %d player(s)" % [town_name, role, player_count]


func _on_peer_connected(peer_id: int) -> void:
	super(peer_id)
	if multiplayer.is_server():
		# Sync all gateway states to the new peer
		_sync_all_gateways_to_peer(peer_id)
		# Sync field cache to the new peer
		_sync_field_cache_to_peer(peer_id)
		# Request CRDT state from returning peer for linked fields
		_request_field_state_from_peer(peer_id)


func _exit_tree() -> void:
	# Disconnect load_completed if still connected (MapManager owns the storage lifecycle)
	if _town_storage != null and _town_storage.load_completed.is_connected(_on_town_load_completed):
		_town_storage.load_completed.disconnect(_on_town_load_completed)
	_town_storage = null

	_disconnect_shared_signals()
	_disconnect_town_signals()


func _disconnect_town_signals() -> void:
	## Disconnect town-specific signals.
	if _town_name_dialog and _town_name_dialog.name_confirmed.is_connected(_on_town_name_confirmed):
		_town_name_dialog.name_confirmed.disconnect(_on_town_name_confirmed)
	if _totem_ui and _totem_ui.edit_name_requested.is_connected(_on_totem_edit_name_requested):
		_totem_ui.edit_name_requested.disconnect(_on_totem_edit_name_requested)
	if _host_travel_warning:
		if _host_travel_warning.confirmed.is_connected(_on_host_travel_confirmed):
			_host_travel_warning.confirmed.disconnect(_on_host_travel_confirmed)
		if _host_travel_warning.cancelled.is_connected(_on_host_travel_cancelled):
			_host_travel_warning.cancelled.disconnect(_on_host_travel_cancelled)
	if NetworkManager.field_cache_received.is_connected(_on_field_cache_received):
		NetworkManager.field_cache_received.disconnect(_on_field_cache_received)
	if NetworkManager.field_travel_requested.is_connected(
		_on_field_travel_requested
	):
		NetworkManager.field_travel_requested.disconnect(
			_on_field_travel_requested
		)
	if NetworkManager.field_travel_approved.is_connected(
		_on_field_travel_approved
	):
		NetworkManager.field_travel_approved.disconnect(
			_on_field_travel_approved
		)
	if NetworkManager.field_state_returned.is_connected(
		_on_field_state_returned
	):
		NetworkManager.field_state_returned.disconnect(
			_on_field_state_returned
		)
	if NetworkManager.field_state_return_requested.is_connected(
		_on_field_state_return_requested
	):
		NetworkManager.field_state_return_requested.disconnect(
			_on_field_state_return_requested
		)
	if P2PSyncManager.crdt_state_received.is_connected(_on_p2p_crdt_state_received):
		P2PSyncManager.crdt_state_received.disconnect(_on_p2p_crdt_state_received)
	if P2PSyncManager.crdt_request_received.is_connected(_on_p2p_crdt_request_received):
		P2PSyncManager.crdt_request_received.disconnect(_on_p2p_crdt_request_received)


# =============================================================================
# Town-Specific Items
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
		# Dict values are provably StringName/Vector3 from the literal above
		@warning_ignore("unsafe_call_argument")
		_spawn_item_at(spawn["id"], spawn["pos"], 1)

	print("Town: Spawned %d initial pearls (one of each type)" % pearl_spawns.size())


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
	## Town gateway config is host-only, so pearl is consumed immediately.
	if _pending_gateway_config == null:
		return

	var gateway: Gateway = _pending_gateway_config
	_pending_gateway_config = null

	# Consume pearl (dialog no longer does this - we consume after validation)
	if not GatewayConfigDialog.consume_pearl_from_inventory(pearl_type):
		push_warning("Town: Failed to consume pearl")
		return

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

	# Broadcast gateway state to all clients
	if multiplayer.is_server():
		NetworkManager.broadcast_gateway_state(
			gateway.gateway_id, 0, field_name, generation_seed, pearl_type, -1
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
		# Client requests field travel approval from town host
		print(
			"Town: Client requesting field travel for gateway %d"
			% gateway.gateway_id
		)
		_pending_travel_gateway = gateway
		NetworkManager.request_field_travel.rpc_id(1, gateway.gateway_id)


func _on_gateway_config_cancelled() -> void:
	_pending_gateway_config = null


func _sync_all_gateways_to_peer(peer_id: int) -> void:
	## Send all gateway states to a specific peer (called when they connect).
	if not multiplayer.is_server():
		return

	for gateway: Gateway in _gateways:
		# Town gateways only link to fields
		var link_type_str: String = "field" if gateway.has_link() else "none"
		NetworkManager.sync_gateway_state_to_peer(
			peer_id,
			gateway.gateway_id,
			gateway.linked_lobby_id,
			gateway.linked_map_name,
			gateway.generation_seed,
			gateway.pearl_type,
			gateway.linked_gateway_id,
			link_type_str
		)


func _on_gateway_state_received(gateway_id: int, data: Dictionary) -> void:
	## Handle gateway state update from server (clients only).
	if multiplayer.is_server():
		return  # Server doesn't need to process its own broadcasts

	if gateway_id < 0 or gateway_id >= _gateways.size():
		return

	var gateway: Gateway = _gateways[gateway_id]
	var lobby_id: int = data.get("linked_lobby_id", 0)
	var map_name: String = data.get("linked_map_name", "")
	var seed_val: int = data.get("generation_seed", 0)
	var pearl_str: String = data.get("pearl_type", "")
	var pearl_type: StringName = StringName(pearl_str) if not pearl_str.is_empty() else &""
	var linked_gw_id: int = data.get("linked_gateway_id", -1)

	if lobby_id > 0:
		# Full link exists
		gateway.set_link(lobby_id, map_name, linked_gw_id)
		gateway.generation_seed = seed_val
		gateway.pearl_type = pearl_type
	elif seed_val > 0:
		# Configured but not yet created
		gateway.set_config(seed_val, map_name, pearl_type)
	else:
		# Cleared
		gateway.clear_link()

	print("Town: Received gateway %d sync from server (lobby=%d, name=%s, target_gw=%d)" % [
		gateway_id, lobby_id, map_name, linked_gw_id
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


func _on_field_cache_received(entries: Array, _remappings: Dictionary) -> void:
	## Handle field cache data received from server.
	if multiplayer.is_server():
		return  # Server doesn't need to receive its own broadcasts

	var cache: FieldStateCache = MapManager.get_field_cache()
	if cache == null:
		return

	cache.merge_entries(entries)
	print("Town: Merged field cache from server")


func _on_lobby_data_received(lobby_id: int, exists: bool) -> void:
	## Handle response from gateway destination validation.
	if _pending_travel_gateway == null:
		return

	# Only process if this is the lobby we're waiting for
	if _pending_travel_gateway.linked_lobby_id != lobby_id:
		return

	var gateway: Gateway = _pending_travel_gateway
	# Note: Don't clear _pending_travel_gateway here - it's needed by _on_host_travel_confirmed
	# It will be cleared when travel is confirmed or cancelled

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
				_pending_travel_gateway = null  # Clear since we're not traveling
				if _toast_ui != null:
					_toast_ui.show_toast("Field is not currently hosted")
		elif gateway.generation_seed > 0:
			# No cache but we have the seed - can recreate the field
			print("Town: Recreating field from seed %d (old lobby %d no longer exists)" % [
				gateway.generation_seed, lobby_id
			])
			if multiplayer.is_server():
				# Host can recreate the field
				_pending_travel_lobby_id = -1  # Special value for "create new"
				_pending_create_seed = gateway.generation_seed
				_pending_create_pearl_type = gateway.pearl_type
				_host_travel_warning.show_warning()
			else:
				# Client requests field travel approval from host
				print(
					"Town: Client requesting field creation for gateway %d"
					% gateway.gateway_id
				)
				NetworkManager.request_field_travel.rpc_id(
					1, gateway.gateway_id
				)
		else:
			# No cached state and no seed - clear the stale link
			print("Town: Destination lobby %d no longer exists, clearing stale link" % lobby_id)
			_pending_travel_gateway = null  # Clear since we're not traveling
			_clear_stale_gateway_link(gateway)


func _on_host_travel_confirmed() -> void:
	## Handle host confirming they want to leave the town.
	var gateway: Gateway = _pending_travel_gateway
	var gateway_id: int = gateway.gateway_id if gateway != null else -1
	var target_gateway_id: int = gateway.linked_gateway_id if gateway != null else -1
	_pending_travel_gateway = null

	if _pending_travel_lobby_id == -1 and _pending_create_seed > 0:
		# Query for existing field before creating a new one
		var field_seed: int = _pending_create_seed
		var pearl_type: StringName = _pending_create_pearl_type
		_pending_create_seed = 0
		_pending_create_pearl_type = &""
		_pending_travel_lobby_id = 0

		var gw_id: int = gateway_id
		var town_name: String = get_town_name()
		var current_lobby: int = LobbyManager.current_lobby_id

		LobbyManager.find_field_by_seed(field_seed, func(
			found_lobby: int
		) -> void:
			MapManager.set_travel_source(
				current_lobby, gw_id, -1, "field"
			)
			if found_lobby > 0:
				# Join existing field instead of creating duplicate
				print(
					("Town: Host joining existing field %d "
					+ "(seed %d) via gateway %d") % [
						found_lobby, field_seed, gw_id
					]
				)
				MapManager.travel_to_field(found_lobby)
			else:
				# No existing field — create new
				print(
					("Town: Host creating field seed %d, "
					+ "pearl %s via gateway %d") % [
						field_seed, pearl_type, gw_id
					]
				)
				MapManager.create_field(
					field_seed, current_lobby,
					gw_id if gw_id >= 0 else 0,
					town_name, pearl_type,
					SteamManager.get_steam_id()
				)
		)
	elif _pending_travel_lobby_id > 0:
		var lobby_id: int = _pending_travel_lobby_id
		_pending_travel_lobby_id = 0
		_pending_create_seed = 0
		_pending_create_pearl_type = &""

		# Set travel source with target gateway so we spawn at the correct field gateway
		MapManager.set_travel_source(
			LobbyManager.current_lobby_id, gateway_id, target_gateway_id, "field"
		)

		# Check if this is a cached field that needs restoration
		if MapManager.has_cached_field(lobby_id):
			print("Town: Host confirmed restoration via gateway %d -> field gateway %d" % [
				gateway_id, target_gateway_id
			])
			@warning_ignore("return_value_discarded")
			MapManager.restore_cached_field(lobby_id)
		else:
			# Travel to existing field
			print("Town: Host confirmed travel to lobby %d via gateway %d -> field gateway %d" % [
				lobby_id, gateway_id, target_gateway_id
			])
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

	# Capture gateway info before clearing pending state
	var gateway_id: int = -1
	var target_gateway_id: int = -1
	if _pending_travel_gateway != null:
		gateway_id = _pending_travel_gateway.gateway_id
		target_gateway_id = _pending_travel_gateway.linked_gateway_id

	_pending_travel_lobby_id = 0
	_pending_travel_gateway = null

	if lobby_id > 0:
		# Set travel source with target gateway so we spawn at the correct field gateway
		MapManager.set_travel_source(
			LobbyManager.current_lobby_id, gateway_id, target_gateway_id, "field"
		)

		print("Town: Travel confirmed to lobby %d via gateway %d -> field gateway %d" % [
			lobby_id, gateway_id, target_gateway_id
		])
		MapManager.travel_to_field(lobby_id)


func _clear_stale_gateway_link(gateway: Gateway) -> void:
	## Clear a gateway link that points to a non-existent lobby.
	gateway.clear_link()

	# Update persistent storage if host
	if multiplayer.is_server() and _town_storage != null:
		_town_storage.clear_gateway_link(gateway.gateway_id)
		# Clean up any orphaned linked field states
		_town_storage.cleanup_orphaned_linked_fields()

	# Show feedback to player
	if _toast_ui != null:
		_toast_ui.show_toast("Destination no longer exists")


# =============================================================================
# Town State Persistence
# =============================================================================

func _init_town_storage() -> void:
	## Initialize town storage reference (host only).
	## Uses the shared instance owned by MapManager. If already loaded
	## (e.g., returning from a field), skips disk I/O.
	_town_storage = MapManager.get_town_storage()

	if MapManager.is_town_storage_loaded():
		# Already loaded (returning from field) - proceed directly
		_on_town_load_completed(true)
	else:
		# First load - connect signal and read from disk
		@warning_ignore("return_value_discarded")
		_town_storage.load_completed.connect(_on_town_load_completed)
		_town_storage.load_state()
		MapManager._town_storage_loaded = true


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

	# Advertise linked field seeds for cross-town discovery
	MapManager.update_town_linked_seeds(_town_storage)

	# Start async field state sync (discover active fields + peer towns)
	_start_field_sync()

	_update_status()


func _start_field_sync() -> void:
	## Initiate async field state sync on town startup.
	## Queries Steam lobbies for active fields and peer towns with
	## overlapping seeds. Results arrive via callbacks.
	if _town_storage == null:
		return

	# Collect configured seeds
	var seeds: Array[int] = []
	for i: int in range(4):
		var gw: Dictionary = _town_storage.get_gateway(i)
		var seed_val: int = gw.get("generation_seed", 0)
		if seed_val > 0:
			seeds.append(seed_val)

	if seeds.is_empty():
		print("Town: No configured gateways, skipping field sync")
		return

	print("Town: Starting field sync for %d seeds" % seeds.size())

	# Connect P2P sync signals (if not already)
	if not P2PSyncManager.crdt_state_received.is_connected(
		_on_p2p_crdt_state_received
	):
		@warning_ignore("return_value_discarded")
		P2PSyncManager.crdt_state_received.connect(
			_on_p2p_crdt_state_received
		)
	if not P2PSyncManager.crdt_request_received.is_connected(
		_on_p2p_crdt_request_received
	):
		@warning_ignore("return_value_discarded")
		P2PSyncManager.crdt_request_received.connect(
			_on_p2p_crdt_request_received
		)


func _on_p2p_crdt_state_received(
	sender_steam_id: int, generation_seed: int, state: Dictionary
) -> void:
	## Handle CRDT state received from another town via P2P.
	if _town_storage == null:
		return

	# Validate the seed matches one of our gateways
	var has_seed: bool = false
	for i: int in range(4):
		var gw: Dictionary = _town_storage.get_gateway(i)
		if gw.get("generation_seed", 0) == generation_seed:
			has_seed = true
			break

	if not has_seed:
		push_warning(
			"Town: Rejected CRDT state for unknown seed %d from %d"
			% [generation_seed, sender_steam_id]
		)
		return

	# Extract CRDT components and merge
	var incoming_removed: Dictionary = state.get("removed_items", {})
	var incoming_placed: Dictionary = state.get("placed_items", {})
	var incoming_gv: Array[int] = [0, 0, 0, 0]
	var gv_data: Variant = state.get("gateway_versions", [])
	if gv_data is Array:
		@warning_ignore("unsafe_cast")
		var gv_arr: Array = gv_data as Array
		for i: int in range(mini(gv_arr.size(), 4)):
			if gv_arr[i] is int:
				incoming_gv[i] = gv_arr[i]
			elif gv_arr[i] is float:
				@warning_ignore("unsafe_call_argument")
				incoming_gv[i] = int(gv_arr[i])
	var incoming_gateways: Array[Dictionary] = []
	var gws_data: Variant = state.get("gateways", [])
	if gws_data is Array:
		@warning_ignore("unsafe_cast")
		for gw: Variant in (gws_data as Array):
			if gw is Dictionary:
				@warning_ignore("unsafe_cast")
				incoming_gateways.append((gw as Dictionary).duplicate())

	_town_storage.merge_linked_field(
		generation_seed, incoming_removed, incoming_placed,
		incoming_gv, incoming_gateways
	)
	print(
		"Town: Merged P2P CRDT state from %d for seed %d"
		% [sender_steam_id, generation_seed]
	)


func _on_p2p_crdt_request_received(
	sender_steam_id: int, generation_seed: int
) -> void:
	## Handle CRDT state request from another town via P2P.
	if _town_storage == null:
		return

	var field_data: Variant = _town_storage.get_linked_field(generation_seed)
	if field_data == null:
		return

	@warning_ignore("unsafe_cast")
	var data: Dictionary = field_data as Dictionary
	@warning_ignore("return_value_discarded")
	P2PSyncManager.send_crdt_state(sender_steam_id, generation_seed, data)
	print(
		"Town: Sent CRDT state to %d for seed %d"
		% [sender_steam_id, generation_seed]
	)


func _on_field_travel_requested(peer_id: int, gateway_id: int) -> void:
	## Server handler: client wants to travel through a configured gateway.
	## Queries for existing field lobby, then sends CRDT state + config.
	if not multiplayer.is_server():
		return

	if gateway_id < 0 or gateway_id >= _gateways.size():
		push_warning(
			"Town: Invalid gateway_id %d from peer %d"
			% [gateway_id, peer_id]
		)
		return

	var gateway: Gateway = _gateways[gateway_id]
	if gateway.generation_seed <= 0:
		push_warning(
			"Town: Gateway %d not configured, rejecting peer %d"
			% [gateway_id, peer_id]
		)
		return

	# Prevent duplicate creation attempts
	if _pending_gateway_creations.has(gateway_id):
		push_warning(
			"Town: Gateway %d creation already pending, rejecting peer %d"
			% [gateway_id, peer_id]
		)
		return

	# Build CRDT state from town cloud storage
	var field_state: Dictionary = {}
	if _town_storage != null:
		var stored: Variant = _town_storage.get_linked_field(
			gateway.generation_seed
		)
		if stored is Dictionary:
			@warning_ignore("unsafe_cast")
			field_state = (stored as Dictionary).duplicate(true)

	var state_json: String = JSON.stringify(field_state)

	# Query for existing field lobby before approving
	var gw_seed: int = gateway.generation_seed
	var gw_pearl: StringName = gateway.pearl_type
	var gw_map: String = gateway.linked_map_name
	var host_id: int = SteamManager.get_steam_id()

	LobbyManager.find_field_by_seed(gw_seed, func(
		found_lobby: int
	) -> void:
		# Only mark pending creation if no existing field
		if found_lobby <= 0:
			_pending_gateway_creations[gateway_id] = true

		print(
			("Town: Approving field travel for peer %d via "
			+ "gateway %d (seed %d, pearl %s, existing=%d)"
			) % [
				peer_id, gateway_id, gw_seed, gw_pearl,
				found_lobby
			]
		)

		NetworkManager.send_field_travel_approval(
			peer_id, gateway_id, gw_seed, gw_pearl, gw_map,
			state_json, host_id, maxi(found_lobby, 0)
		)

		# Update gateway link if an existing field was found
		if found_lobby > 0:
			gateway.set_link(
				found_lobby, gw_map, gateway.linked_gateway_id
			)
			gateway.generation_seed = gw_seed
			gateway.pearl_type = gw_pearl

		# Clear pending after a timeout
		if found_lobby <= 0:
			@warning_ignore("return_value_discarded")
			get_tree().create_timer(60.0).timeout.connect(
				func() -> void:
					@warning_ignore("return_value_discarded")
					_pending_gateway_creations.erase(gateway_id)
			)
	)


func _on_field_travel_approved(
	gateway_id: int, generation_seed: int, pearl_type: String,
	_map_name: String, field_state_json: String,
	host_steam_id: int, existing_field_lobby: int
) -> void:
	## Client handler: server approved our field travel request.
	## Joins existing field if available, otherwise creates new.
	if multiplayer.is_server():
		return

	if gateway_id < 0 or gateway_id >= _gateways.size():
		return

	# Parse CRDT state from server
	var field_state: Dictionary = {}
	if not field_state_json.is_empty():
		var parsed: Variant = JSON.parse_string(field_state_json)
		if parsed is Dictionary:
			@warning_ignore("unsafe_cast")
			field_state = parsed as Dictionary

	# Store CRDT state for the field to consume
	if not field_state.is_empty():
		MapManager.set_pending_field_crdt(field_state)

	# Set travel source so destination knows where we came from
	MapManager.set_travel_source(
		LobbyManager.current_lobby_id, gateway_id, -1, "field"
	)

	if existing_field_lobby > 0:
		# Join existing field lobby instead of creating a new one
		print(
			("Town: Client joining existing field %d from approval "
			+ "(seed %d, gateway %d)") % [
				existing_field_lobby, generation_seed, gateway_id
			]
		)
		MapManager.travel_to_field(existing_field_lobby)
	else:
		# Create new field with town HOST's Steam ID as origin owner
		print(
			("Town: Client creating field from approval "
			+ "(seed %d, pearl %s, gateway %d, host %d)") % [
				generation_seed, pearl_type, gateway_id,
				host_steam_id
			]
		)
		var pearl_sn: StringName = (
			StringName(pearl_type) if not pearl_type.is_empty()
			else &""
		)
		MapManager.create_field(
			generation_seed,
			LobbyManager.current_lobby_id,
			gateway_id,
			get_town_name(),
			pearl_sn,
			host_steam_id
		)


func _request_field_state_from_peer(peer_id: int) -> void:
	## Server: request CRDT state from a returning peer for our gateway seeds.
	if not multiplayer.is_server() or _town_storage == null:
		return

	var seeds: Array[int] = []
	for i: int in range(4):
		var gw: Dictionary = _town_storage.get_gateway(i)
		var seed_val: int = gw.get("generation_seed", 0)
		if seed_val > 0:
			seeds.append(seed_val)

	if seeds.is_empty():
		return

	var seeds_json: String = JSON.stringify(seeds)
	NetworkManager.request_field_state_on_return.rpc_id(
		peer_id, seeds_json
	)
	print(
		"Town: Requested field state from peer %d for %d seeds"
		% [peer_id, seeds.size()]
	)


func _on_field_state_return_requested(seeds_json: String) -> void:
	## Client: server wants our CRDT state for matching seeds.
	## Look up field cache for entries with matching generation_seed.
	if multiplayer.is_server():
		return

	var seeds: Array = []
	var parsed: Variant = JSON.parse_string(seeds_json)
	if parsed is Array:
		@warning_ignore("unsafe_cast")
		seeds = parsed as Array

	if seeds.is_empty():
		return

	var cache: FieldStateCache = MapManager.get_field_cache()
	if cache == null:
		return

	var matching_entries: Array[Dictionary] = []
	for lobby_id: int in cache.get_cached_lobby_ids():
		var entry: Dictionary = cache.serialize_entry(lobby_id)
		if entry.is_empty():
			continue
		var entry_seed: Variant = entry.get("generation_seed", 0)
		# Seeds from JSON parse may be float; compare flexibly
		for seed_val: Variant in seeds:
			@warning_ignore("unsafe_call_argument")
			if int(entry_seed) == int(seed_val) and int(seed_val) > 0:
				matching_entries.append(entry)
				break

	if matching_entries.is_empty():
		return

	var entries_json: String = JSON.stringify(matching_entries)
	NetworkManager.return_field_state.rpc_id(1, entries_json)
	print(
		"Town: Returning %d field cache entries to server"
		% matching_entries.size()
	)


func _on_field_state_returned(
	peer_id: int, entries_json: String
) -> void:
	## Server: merge returned CRDT state into town storage.
	if not multiplayer.is_server() or _town_storage == null:
		return

	var parsed: Variant = JSON.parse_string(entries_json)
	if not parsed is Array:
		return

	@warning_ignore("unsafe_cast")
	var entries: Array = parsed as Array

	for entry_variant: Variant in entries:
		if not entry_variant is Dictionary:
			continue

		@warning_ignore("unsafe_cast")
		var data: Dictionary = entry_variant as Dictionary
		var seed_val: int = data.get("generation_seed", 0)
		if seed_val <= 0:
			continue

		# Validate seed matches one of our gateways
		var matching_gw_id: int = -1
		for i: int in range(4):
			var gw: Dictionary = _town_storage.get_gateway(i)
			if gw.get("generation_seed", 0) == seed_val:
				matching_gw_id = i
				break
		if matching_gw_id < 0:
			continue

		# Extract CRDT components
		var incoming_removed: Dictionary = {}
		var rem: Variant = data.get("removed_items", {})
		if rem is Dictionary:
			@warning_ignore("unsafe_cast")
			incoming_removed = rem as Dictionary

		var incoming_placed: Dictionary = {}
		var plc: Variant = data.get("placed_items", {})
		if plc is Dictionary:
			@warning_ignore("unsafe_cast")
			incoming_placed = plc as Dictionary

		var incoming_gv: Array[int] = [0, 0, 0, 0]
		var gv_data: Variant = data.get("gateway_versions", [])
		if gv_data is Array:
			@warning_ignore("unsafe_cast")
			var gv_arr: Array = gv_data as Array
			for i: int in range(mini(gv_arr.size(), 4)):
				if gv_arr[i] is int:
					incoming_gv[i] = gv_arr[i]
				elif gv_arr[i] is float:
					@warning_ignore("unsafe_call_argument")
					incoming_gv[i] = int(gv_arr[i])

		var incoming_gateways: Array[Dictionary] = []
		var gws: Variant = data.get("gateways", [])
		if gws is Array:
			@warning_ignore("unsafe_cast")
			for gw: Variant in (gws as Array):
				if gw is Dictionary:
					@warning_ignore("unsafe_cast")
					incoming_gateways.append(
						(gw as Dictionary).duplicate()
					)

		# Merge into town storage
		_town_storage.merge_linked_field(
			seed_val, incoming_removed, incoming_placed,
			incoming_gv, incoming_gateways
		)

		# Update linked_lobby_id if the peer reports a live field
		var lobby_id: int = data.get("lobby_id", 0)
		if lobby_id > 0 and matching_gw_id >= 0:
			var gw: Dictionary = _town_storage.get_gateway(matching_gw_id)
			var current_link: String = gw.get("linked_lobby_id", "0")
			var linked_map: String = str(gw.get("linked_map_name", ""))
			# gw.get() returns Variant; value is always int from gateway dict
			@warning_ignore("unsafe_call_argument")
			var linked_gw_id: int = int(gw.get("linked_gateway_id", -1))
			if current_link == "0" or current_link.to_int() != lobby_id:
				_town_storage.set_gateway_link(
					matching_gw_id, lobby_id, linked_map
				)
				# Update the gateway UI
				if matching_gw_id < _gateways.size():
					_gateways[matching_gw_id].set_link(
						lobby_id, linked_map, linked_gw_id
					)

		# Also merge into field cache
		var cache: FieldStateCache = MapManager.get_field_cache()
		if cache != null:
			@warning_ignore("return_value_discarded")
			cache.merge_entry(data)

		print(
			("Town: Merged returned field state from peer %d "
			+ "for seed %d") % [peer_id, seed_val]
		)

	# Push updated state to peer towns via P2P
	_push_state_to_peer_towns()


func _push_state_to_peer_towns() -> void:
	## Push updated field state to known peer towns via P2P.
	## Queries lobbies for towns with matching seeds and sends state.
	if _town_storage == null:
		return

	# Collect seeds and their stored state
	for i: int in range(4):
		var gw: Dictionary = _town_storage.get_gateway(i)
		var seed_val: int = gw.get("generation_seed", 0)
		if seed_val <= 0:
			continue

		var stored: Variant = _town_storage.get_linked_field(seed_val)
		if stored == null or not stored is Dictionary:
			continue

		# P2P push happens when peer towns are discovered during sync.
		# The _start_field_sync() mechanism handles ongoing discovery.
		# Here we just ensure our local state is saved for when
		# peer towns query us via P2P.


func _restore_gateway_links() -> void:
	## Restore gateway links and configurations from saved town state.
	if _town_storage == null:
		return

	for i: int in range(_gateways.size()):
		var gateway_data: Dictionary = _town_storage.get_gateway(i)
		# linked_lobby_id is stored as string to preserve precision for large Steam lobby IDs
		var lobby_id_value: Variant = gateway_data.get("linked_lobby_id", "0")
		var lobby_id: int = 0
		if lobby_id_value is String:
			@warning_ignore("unsafe_cast")
			lobby_id = (lobby_id_value as String).to_int()
		elif lobby_id_value is int or lobby_id_value is float:
			# Type-narrowed Variant; int() cast is safe after is-check
			@warning_ignore("unsafe_call_argument")
			lobby_id = int(lobby_id_value)
		var map_name: String = gateway_data.get("linked_map_name", "")
		var field_seed: int = gateway_data.get("generation_seed", 0)
		var pearl_type_str: String = gateway_data.get("pearl_type", "")
		var pearl_type: StringName = StringName(pearl_type_str) if not pearl_type_str.is_empty() else &""
		var linked_gateway_id: int = gateway_data.get("linked_gateway_id", -1)

		if lobby_id > 0:
			# Has a created field - pass linked_gateway_id to track which field gateway to arrive at
			_gateways[i].set_link(lobby_id, map_name, linked_gateway_id)
			_gateways[i].generation_seed = field_seed
			_gateways[i].pearl_type = pearl_type
			print("Town: Restored gateway %d link to %s (lobby %d, field_gw %d, pearl %s)" % [
				i, map_name, lobby_id, linked_gateway_id, pearl_type
			])
		elif field_seed > 0 and not map_name.is_empty():
			# Configured but field not created yet
			_gateways[i].set_config(field_seed, map_name, pearl_type)
			_gateways[i].linked_gateway_id = linked_gateway_id
			print("Town: Restored gateway %d config for %s (seed %d, field_gw %d, pearl %s)" % [
				i, map_name, field_seed, linked_gateway_id, pearl_type
			])


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
		# Clean up any orphaned linked field states
		_town_storage.cleanup_orphaned_linked_fields()

	# Broadcast cleared gateway state to all clients
	NetworkManager.broadcast_gateway_state(gateway_id, 0, "", 0, &"", -1)

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
