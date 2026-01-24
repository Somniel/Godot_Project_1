class_name TotemUI
extends Control
## UI panel for totem interaction. Shows map info and gateway connections.

signal closed
signal edit_name_requested
signal gateway_clear_requested(gateway_id: int)

const DIRECTION_NAMES: Array[String] = ["North", "East", "South", "West"]

@onready var _town_name_label: Label = $Panel/VBoxContainer/TownNameContainer/TownNameLabel
@onready var _edit_name_button: Button = $Panel/VBoxContainer/TownNameContainer/EditNameButton
@onready var _player_count_label: Label = $Panel/VBoxContainer/PlayerCountLabel
@onready var _host_label: Label = $Panel/VBoxContainer/HostLabel
@onready var _close_button: Button = $Panel/VBoxContainer/CloseButton
@onready var _gateways_container: VBoxContainer = $Panel/VBoxContainer/GatewaysContainer

var _is_host: bool = false
var _gateway_rows: Array[HBoxContainer] = []
var _gateway_labels: Array[Label] = []
var _gateway_clear_buttons: Array[Button] = []


func _ready() -> void:
	visible = false
	@warning_ignore("return_value_discarded")
	_edit_name_button.pressed.connect(_on_edit_name_pressed)
	@warning_ignore("return_value_discarded")
	_close_button.pressed.connect(_on_close_pressed)

	# Get references to gateway UI elements
	_gateway_rows = [
		$Panel/VBoxContainer/GatewaysContainer/NorthGateway,
		$Panel/VBoxContainer/GatewaysContainer/EastGateway,
		$Panel/VBoxContainer/GatewaysContainer/SouthGateway,
		$Panel/VBoxContainer/GatewaysContainer/WestGateway,
	]

	for i in range(4):
		var row: HBoxContainer = _gateway_rows[i]
		var dest_label: Label = row.get_node("DestinationLabel")
		var clear_button: Button = row.get_node("ClearButton")

		_gateway_labels.append(dest_label)
		_gateway_clear_buttons.append(clear_button)

		# Connect clear button with gateway ID
		@warning_ignore("return_value_discarded")
		clear_button.pressed.connect(_on_clear_pressed.bind(i))


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


## Show the totem UI with current map info
func show_ui(map_name: String, player_count: int, host_name: String, is_host: bool) -> void:
	_is_host = is_host
	_town_name_label.text = map_name if not map_name.is_empty() else "Unnamed"
	_player_count_label.text = "Players: %d" % player_count
	_host_label.text = "Host: %s" % host_name

	# Only show edit button for host (and only for towns, not fields)
	_edit_name_button.visible = is_host

	visible = true


## Set gateway connection data
## gateways: Array of dictionaries with keys: linked_map_name, has_link, is_origin
func set_gateway_data(gateways: Array[Dictionary], can_clear: bool) -> void:
	for i in range(min(4, gateways.size())):
		var gateway_data: Dictionary = gateways[i]
		var has_link: bool = gateway_data.get("has_link", false)
		var map_name: String = gateway_data.get("linked_map_name", "")
		var is_origin: bool = gateway_data.get("is_origin", false)

		if has_link:
			_gateway_labels[i].text = map_name if not map_name.is_empty() else "Linked"
		else:
			_gateway_labels[i].text = "Not connected"

		# Show clear button only if host, has a link, and not an origin gateway
		_gateway_clear_buttons[i].visible = can_clear and has_link and not is_origin


## Update the displayed map name
func update_town_name(town_name: String) -> void:
	_town_name_label.text = town_name if not town_name.is_empty() else "Unnamed"


func _close() -> void:
	visible = false
	closed.emit()


func _on_edit_name_pressed() -> void:
	edit_name_requested.emit()


func _on_close_pressed() -> void:
	_close()


func _on_clear_pressed(gateway_id: int) -> void:
	gateway_clear_requested.emit(gateway_id)
