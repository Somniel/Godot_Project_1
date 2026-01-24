extends Control
## Main menu scene handling host, browse, and quit actions.


@onready var _status_label: Label = $VBoxContainer/StatusLabel
@onready var _host_button: Button = $VBoxContainer/HostButton
@onready var _browse_button: Button = $VBoxContainer/BrowseButton
@onready var _main_menu_container: VBoxContainer = $VBoxContainer

# Lobby browser panel
@onready var _lobby_browser_panel: Panel = $LobbyBrowserPanel
@onready var _lobby_list: ItemList = $LobbyBrowserPanel/VBoxContainer/LobbyList
@onready var _lobby_info_label: Label = $LobbyBrowserPanel/VBoxContainer/LobbyInfoLabel
@onready var _join_button: Button = $LobbyBrowserPanel/VBoxContainer/ButtonContainer/JoinButton

var _available_lobbies: Array = []
var _selected_lobby_index: int = -1


func _ready() -> void:
	# Disable multiplayer buttons until Steam connects
	_set_multiplayer_buttons_enabled(false)

	# Steam signals
	@warning_ignore("return_value_discarded")
	SteamManager.steam_initialized.connect(_on_steam_initialized)
	@warning_ignore("return_value_discarded")
	SteamManager.steam_init_failed.connect(_on_steam_init_failed)

	# Lobby signals
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_created.connect(_on_lobby_created)
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_create_failed.connect(_on_lobby_create_failed)
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_joined.connect(_on_lobby_joined)
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_join_failed.connect(_on_lobby_join_failed)
	@warning_ignore("return_value_discarded")
	LobbyManager.lobby_list_received.connect(_on_lobby_list_received)

	# Network signals
	@warning_ignore("return_value_discarded")
	NetworkManager.host_started.connect(_on_host_started)
	@warning_ignore("return_value_discarded")
	NetworkManager.client_started.connect(_on_client_started)
	@warning_ignore("return_value_discarded")
	NetworkManager.connection_failed.connect(_on_connection_failed)

	# Check if Steam init already completed (signal may have fired before scene loaded)
	if SteamManager.is_steam_initialized:
		_on_steam_initialized()
	elif SteamManager.init_attempted and SteamManager.init_error != "":
		_on_steam_init_failed(SteamManager.init_error)
	else:
		_update_status("Initializing Steam...")


func _on_steam_initialized() -> void:
	_update_status("Connected as: %s" % SteamManager.get_steam_username())
	_set_multiplayer_buttons_enabled(true)


func _on_steam_init_failed(reason: String) -> void:
	_update_status("Steam offline: %s" % reason)
	_set_multiplayer_buttons_enabled(false)


func _on_host_button_pressed() -> void:
	_update_status("Hosting town...")
	_set_multiplayer_buttons_enabled(false)
	MapManager.host_town()


func _on_browse_button_pressed() -> void:
	_show_lobby_browser()
	_refresh_lobby_list()


func _on_quit_button_pressed() -> void:
	get_tree().quit()


func _on_lobby_created(lobby_id: int) -> void:
	_update_status("Lobby created: %d" % lobby_id)


func _on_lobby_create_failed(reason: String) -> void:
	_update_status("Failed to create lobby: %s" % reason)
	_set_multiplayer_buttons_enabled(true)


func _on_lobby_joined(lobby_id: int) -> void:
	_update_status("Joined lobby: %d" % lobby_id)


func _on_lobby_list_received(lobbies: Array) -> void:
	_available_lobbies = lobbies
	_populate_lobby_list()


func _on_lobby_join_failed(reason: String) -> void:
	_update_status("Failed to join: %s" % reason)
	_lobby_info_label.text = "Failed to join: %s" % reason
	_set_multiplayer_buttons_enabled(true)


func _on_host_started() -> void:
	_update_status("Hosting! Loading world...")
	# MapManager handles scene transition


func _on_client_started() -> void:
	_update_status("Connected! Loading world...")
	# MapManager handles scene transition


func _on_connection_failed(reason: String) -> void:
	_update_status("Connection failed: %s" % reason)
	_set_multiplayer_buttons_enabled(true)


func _update_status(message: String) -> void:
	_status_label.text = message


func _set_multiplayer_buttons_enabled(enabled: bool) -> void:
	_host_button.disabled = not enabled
	_browse_button.disabled = not enabled


# Lobby browser functions

func _show_lobby_browser() -> void:
	_main_menu_container.visible = false
	_lobby_browser_panel.visible = true
	_clear_lobby_selection()


func _hide_lobby_browser() -> void:
	_lobby_browser_panel.visible = false
	_main_menu_container.visible = true


func _refresh_lobby_list() -> void:
	_lobby_list.clear()
	_lobby_info_label.text = "Fetching servers..."
	_clear_lobby_selection()
	LobbyManager.request_lobby_list()


func _populate_lobby_list() -> void:
	_lobby_list.clear()
	_clear_lobby_selection()

	if _available_lobbies.is_empty():
		_lobby_info_label.text = "No towns found"
		return

	# Filter to only show town lobbies (not fields)
	var town_lobbies: Array = []
	for i in range(_available_lobbies.size()):
		var lobby_id: int = _available_lobbies[i]
		var server_type: String = LobbyManager.get_lobby_metadata(lobby_id, "server_type")

		# Include lobbies that are towns or have no server_type (legacy/default)
		if server_type.is_empty() or server_type == MapManager.MAP_TYPE_TOWN:
			town_lobbies.append(lobby_id)

	# Store filtered list for selection handling
	_available_lobbies = town_lobbies

	if town_lobbies.is_empty():
		_lobby_info_label.text = "No towns found"
		return

	for i in range(town_lobbies.size()):
		var lobby_id: int = town_lobbies[i]
		var server_name: String = LobbyManager.get_lobby_metadata(lobby_id, "server_name")
		var player_count: int = LobbyManager.get_lobby_member_count(lobby_id)

		if server_name.is_empty():
			server_name = "Unknown Town"

		var display_text: String = "%s (%d players)" % [server_name, player_count]
		@warning_ignore("return_value_discarded")
		_lobby_list.add_item(display_text)

	_lobby_info_label.text = "Found %d town(s)" % town_lobbies.size()


func _clear_lobby_selection() -> void:
	_selected_lobby_index = -1
	_join_button.disabled = true
	_lobby_list.deselect_all()


func _on_lobby_list_item_selected(index: int) -> void:
	_selected_lobby_index = index
	_join_button.disabled = false

	if index >= 0 and index < _available_lobbies.size():
		var lobby_id: int = _available_lobbies[index]
		var server_name: String = LobbyManager.get_lobby_metadata(lobby_id, "server_name")
		var player_count: int = LobbyManager.get_lobby_member_count(lobby_id)

		if server_name.is_empty():
			server_name = "Unknown Server"

		_lobby_info_label.text = "%s - %d player(s)" % [server_name, player_count]


func _on_refresh_button_pressed() -> void:
	_refresh_lobby_list()


func _on_join_button_pressed() -> void:
	if _selected_lobby_index < 0 or _selected_lobby_index >= _available_lobbies.size():
		return

	var lobby_id: int = _available_lobbies[_selected_lobby_index]
	_lobby_info_label.text = "Joining..."
	_join_button.disabled = true
	LobbyManager.join_lobby(lobby_id)


func _on_back_button_pressed() -> void:
	# If we're in a lobby (joining in progress), leave it
	if LobbyManager.current_lobby_id != 0:
		LobbyManager.leave_lobby()
	_hide_lobby_browser()


func _exit_tree() -> void:
	# Disconnect all signals to prevent orphaned connections
	if SteamManager.steam_initialized.is_connected(_on_steam_initialized):
		SteamManager.steam_initialized.disconnect(_on_steam_initialized)
	if SteamManager.steam_init_failed.is_connected(_on_steam_init_failed):
		SteamManager.steam_init_failed.disconnect(_on_steam_init_failed)
	if LobbyManager.lobby_created.is_connected(_on_lobby_created):
		LobbyManager.lobby_created.disconnect(_on_lobby_created)
	if LobbyManager.lobby_create_failed.is_connected(_on_lobby_create_failed):
		LobbyManager.lobby_create_failed.disconnect(_on_lobby_create_failed)
	if LobbyManager.lobby_joined.is_connected(_on_lobby_joined):
		LobbyManager.lobby_joined.disconnect(_on_lobby_joined)
	if LobbyManager.lobby_join_failed.is_connected(_on_lobby_join_failed):
		LobbyManager.lobby_join_failed.disconnect(_on_lobby_join_failed)
	if LobbyManager.lobby_list_received.is_connected(_on_lobby_list_received):
		LobbyManager.lobby_list_received.disconnect(_on_lobby_list_received)
	if NetworkManager.host_started.is_connected(_on_host_started):
		NetworkManager.host_started.disconnect(_on_host_started)
	if NetworkManager.client_started.is_connected(_on_client_started):
		NetworkManager.client_started.disconnect(_on_client_started)
	if NetworkManager.connection_failed.is_connected(_on_connection_failed):
		NetworkManager.connection_failed.disconnect(_on_connection_failed)
