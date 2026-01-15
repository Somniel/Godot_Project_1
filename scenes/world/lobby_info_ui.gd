class_name LobbyInfoUI
extends Control
## UI panel displaying current lobby information.
## Shows lobby ID and connected players.

@onready var _lobby_id_label: Label = $Panel/VBoxContainer/LobbyIdLabel
@onready var _players_list: ItemList = $Panel/VBoxContainer/PlayersList

## Cache for player names to reduce Steam API calls
var _player_name_cache: Dictionary = {}


func _ready() -> void:
	visible = false


func show_lobby_info() -> void:
	_refresh_info()
	visible = true


func hide_lobby_info() -> void:
	visible = false


func clear_cache() -> void:
	## Clears the player name cache. Call when leaving a lobby.
	_player_name_cache.clear()


func _refresh_info() -> void:
	var lobby_id: int = LobbyManager.current_lobby_id

	if not Utils.is_valid_lobby_id(lobby_id):
		_lobby_id_label.text = "Not in a lobby"
		_players_list.clear()
		return

	_lobby_id_label.text = "Lobby ID: %d" % lobby_id
	_players_list.clear()

	var members: Array[int] = LobbyManager.get_lobby_members(lobby_id)

	for member_steam_id: int in members:
		var player_name: String = _get_cached_player_name(member_steam_id)
		@warning_ignore("return_value_discarded")
		_players_list.add_item(Utils.sanitize_display_string(player_name))


func _get_cached_player_name(steam_id: int) -> String:
	## Returns player name from cache or fetches from Steam API.
	if _player_name_cache.has(steam_id):
		return _player_name_cache[steam_id]

	var player_name: String = "Unknown"
	var steam: Object = SteamManager.get_steam()
	if steam != null:
		@warning_ignore("unsafe_method_access")
		player_name = steam.getFriendPersonaName(steam_id)

	_player_name_cache[steam_id] = player_name
	return player_name


func _on_close_button_pressed() -> void:
	hide_lobby_info()


func _on_refresh_button_pressed() -> void:
	_refresh_info()
