class_name GatewayConfigDialog
extends Control
## Dialog for configuring gateway links by sacrificing a pearl or linking to town.
## The pearl type determines the field's theme and visuals.

## Emitted when player confirms gateway configuration (create new field)
signal gateway_configured(generation_seed: int, field_name: String, pearl_type: StringName)

## Emitted when player wants to link to their town gateway
signal town_link_requested(town_gateway_id: int)

## Emitted when dialog is cancelled
signal cancelled

## Dialog mode
enum Mode { CREATE_FIELD, LINK_TOWN }

## Pearl types that can be sacrificed
const PEARL_TYPES: Array[StringName] = [
	&"flame_pearl",
	&"air_pearl",
	&"life_pearl",
	&"water_pearl"
]

## Display names for pearls
const PEARL_DISPLAY_NAMES: Dictionary = {
	&"flame_pearl": "Flame Pearl",
	&"air_pearl": "Air Pearl",
	&"life_pearl": "Life Pearl",
	&"water_pearl": "Water Pearl"
}

## Auto-generated field names based on pearl type
const PEARL_FIELD_NAMES: Dictionary = {
	&"flame_pearl": "Flame Field",
	&"air_pearl": "Sky Field",
	&"life_pearl": "Verdant Field",
	&"water_pearl": "Aqua Field"
}

## Direction names for gateways
const DIRECTION_NAMES: Array[String] = ["North", "East", "South", "West"]

@onready var _title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var _pearl_option: OptionButton = $Panel/VBoxContainer/PearlContainer/PearlOption
@onready var _no_pearls_label: Label = $Panel/VBoxContainer/PearlContainer/NoPearlsLabel
@onready var _create_button: Button = $Panel/VBoxContainer/ButtonContainer/CreateButton
@onready var _cancel_button: Button = $Panel/VBoxContainer/ButtonContainer/CancelButton

# Town link mode UI elements (created dynamically if needed)
var _mode_container: HBoxContainer = null
var _create_field_button: Button = null
var _link_town_button: Button = null
var _town_link_container: VBoxContainer = null
var _town_gateway_option: OptionButton = null
var _warning_label: Label = null
var _confirm_link_button: Button = null

var _gateway_id: int = 0
var _gateway_direction: String = ""
var _available_pearls: Array[StringName] = []
var _selected_pearl_type: StringName = &""

# Town link mode state
var _mode: Mode = Mode.CREATE_FIELD
var _town_gateways: Array[Dictionary] = []
var _selected_town_gateway_id: int = -1
var _has_town_link_ui: bool = false


func _ready() -> void:
	visible = false
	@warning_ignore("return_value_discarded")
	_pearl_option.item_selected.connect(_on_pearl_option_item_selected)
	@warning_ignore("return_value_discarded")
	_create_button.pressed.connect(_on_create_button_pressed)
	@warning_ignore("return_value_discarded")
	_cancel_button.pressed.connect(_on_cancel_button_pressed)
	@warning_ignore("return_value_discarded")
	InventoryManager.inventory_changed.connect(_on_inventory_changed)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


## Show the dialog for configuring a gateway
func show_for_gateway(gateway_id: int, direction: String) -> void:
	_gateway_id = gateway_id
	_gateway_direction = direction
	_title_label.text = "Configure %s Gateway" % direction

	_update_pearl_options()
	visible = true

	# Register with UI manager to block player input
	UIManager.register_blocking_ui()

	# Defer focus grab to prevent the interaction key from being captured
	call_deferred("_deferred_grab_focus")


func _deferred_grab_focus() -> void:
	if visible and _pearl_option != null and _pearl_option.visible:
		_pearl_option.grab_focus()


func _update_pearl_options() -> void:
	_pearl_option.clear()
	_available_pearls.clear()

	for pearl_id: StringName in PEARL_TYPES:
		if InventoryManager.has_item(pearl_id, 1):
			var count: int = InventoryManager.get_item_count(pearl_id)
			var display: String = "%s (x%d)" % [PEARL_DISPLAY_NAMES.get(pearl_id, str(pearl_id)), count]
			_pearl_option.add_item(display)
			_available_pearls.append(pearl_id)

	var has_pearls: bool = not _available_pearls.is_empty()
	_pearl_option.visible = has_pearls
	_no_pearls_label.visible = not has_pearls

	if has_pearls:
		_selected_pearl_type = _available_pearls[0]
	else:
		_selected_pearl_type = &""

	_validate_inputs()


func _validate_inputs() -> void:
	var pearl_valid: bool = _selected_pearl_type != &""
	_create_button.disabled = not pearl_valid


func _close() -> void:
	visible = false

	# Unregister from UI manager to allow player input
	UIManager.unregister_blocking_ui()

	cancelled.emit()


func _generate_seed_from_pearl(pearl_type: StringName) -> int:
	## Generate a seed based on pearl type hash + random value
	var rng := RandomNumberGenerator.new()
	rng.randomize()
	var seed_value: int = hash(pearl_type) ^ rng.randi()
	return absi(seed_value % 1000000)


func _get_field_name_for_pearl(pearl_type: StringName) -> String:
	## Get the auto-generated field name for a pearl type
	return PEARL_FIELD_NAMES.get(pearl_type, "Unknown Field")


static func consume_pearl_from_inventory(pearl_type: StringName) -> bool:
	## Find and remove one pearl from inventory. Returns true if successful.
	for i: int in range(InventoryManager.INVENTORY_SIZE):
		var slot: Dictionary = InventoryManager.get_slot(i)
		if not slot.is_empty():
			# Autoload is always an instance reference; no class_name to call on
			@warning_ignore("static_called_on_instance")
			var item_id: StringName = InventoryManager.get_slot_item_id(slot)
			if item_id == pearl_type:
				return InventoryManager.remove_from_slot(i, 1)
	return false


func _on_pearl_option_item_selected(index: int) -> void:
	if index >= 0 and index < _available_pearls.size():
		_selected_pearl_type = _available_pearls[index]
	_validate_inputs()


func _on_create_button_pressed() -> void:
	if _selected_pearl_type == &"":
		return

	var pearl_to_use: StringName = _selected_pearl_type

	# Generate seed and name based on pearl type
	var seed_value: int = _generate_seed_from_pearl(pearl_to_use)
	var field_name: String = _get_field_name_for_pearl(pearl_to_use)

	visible = false

	# Unregister from UI manager to allow player input
	UIManager.unregister_blocking_ui()

	# Pearl is NOT consumed here - the map scene consumes it after
	# server confirms the configuration (or immediately if we are the server)
	gateway_configured.emit(seed_value, field_name, pearl_to_use)


func _on_cancel_button_pressed() -> void:
	_close()


func _on_inventory_changed() -> void:
	if visible and _mode == Mode.CREATE_FIELD:
		_update_pearl_options()


# =============================================================================
# Town Link Mode (for field gateways)
# =============================================================================

## Show the dialog for configuring a field gateway (includes town link option)
func show_for_field_gateway(gateway_id: int, direction: String,
							town_gateways: Array[Dictionary]) -> void:
	_gateway_id = gateway_id
	_gateway_direction = direction
	_town_gateways = town_gateways
	_mode = Mode.CREATE_FIELD
	_title_label.text = "Configure %s Gateway" % direction

	# Create town link UI if we have town gateways and haven't created it yet
	if not _has_town_link_ui and not town_gateways.is_empty():
		_create_town_link_ui()

	_update_pearl_options()
	_update_mode_visibility()

	visible = true
	UIManager.register_blocking_ui()
	call_deferred("_deferred_grab_focus")


func _create_town_link_ui() -> void:
	## Create the UI elements for town link mode.
	var vbox: VBoxContainer = $Panel/VBoxContainer
	if vbox == null:
		return

	# Find the position to insert mode selector (after HSeparator, before PearlContainer)
	var separator_idx: int = -1
	for i: int in range(vbox.get_child_count()):
		if vbox.get_child(i).name == "HSeparator":
			separator_idx = i
			break

	# Create mode selector container
	_mode_container = HBoxContainer.new()
	_mode_container.name = "ModeContainer"
	_mode_container.alignment = BoxContainer.ALIGNMENT_CENTER
	_mode_container.add_theme_constant_override("separation", 10)

	_create_field_button = Button.new()
	_create_field_button.text = "Create Field"
	_create_field_button.toggle_mode = true
	_create_field_button.button_pressed = true
	@warning_ignore("return_value_discarded")
	_create_field_button.pressed.connect(_on_mode_create_field_pressed)

	_link_town_button = Button.new()
	_link_town_button.text = "Link to Town"
	_link_town_button.toggle_mode = true
	@warning_ignore("return_value_discarded")
	_link_town_button.pressed.connect(_on_mode_link_town_pressed)

	_mode_container.add_child(_create_field_button)
	_mode_container.add_child(_link_town_button)

	if separator_idx >= 0:
		vbox.add_child(_mode_container)
		vbox.move_child(_mode_container, separator_idx + 1)

	# Create town link container (below mode selector)
	_town_link_container = VBoxContainer.new()
	_town_link_container.name = "TownLinkContainer"
	_town_link_container.visible = false

	var gateway_label := Label.new()
	gateway_label.text = "Select your town gateway:"

	_town_gateway_option = OptionButton.new()
	@warning_ignore("return_value_discarded")
	_town_gateway_option.item_selected.connect(_on_town_gateway_selected)

	_warning_label = Label.new()
	_warning_label.name = "WarningLabel"
	_warning_label.add_theme_color_override("font_color", Color(1.0, 0.7, 0.3))
	_warning_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_warning_label.visible = false

	_confirm_link_button = Button.new()
	_confirm_link_button.text = "Link to Town"
	_confirm_link_button.custom_minimum_size = Vector2(100, 0)
	@warning_ignore("return_value_discarded")
	_confirm_link_button.pressed.connect(_on_confirm_link_pressed)

	_town_link_container.add_child(gateway_label)
	_town_link_container.add_child(_town_gateway_option)
	_town_link_container.add_child(_warning_label)
	_town_link_container.add_child(_confirm_link_button)

	# Insert after mode container
	if _mode_container != null:
		var mode_idx: int = _mode_container.get_index()
		vbox.add_child(_town_link_container)
		vbox.move_child(_town_link_container, mode_idx + 1)

	_has_town_link_ui = true


func _update_mode_visibility() -> void:
	## Update UI visibility based on current mode.
	# Show/hide mode selector only if we have town link UI
	if _mode_container != null:
		_mode_container.visible = not _town_gateways.is_empty()

	# Update mode button states
	if _create_field_button != null:
		_create_field_button.button_pressed = (_mode == Mode.CREATE_FIELD)
	if _link_town_button != null:
		_link_town_button.button_pressed = (_mode == Mode.LINK_TOWN)

	# Show/hide appropriate sections
	var pearl_container: Control = $Panel/VBoxContainer/PearlContainer as Control
	var info_label: Control = $Panel/VBoxContainer/InfoLabel as Control
	var button_container: Control = $Panel/VBoxContainer/ButtonContainer as Control

	if pearl_container != null:
		pearl_container.visible = (_mode == Mode.CREATE_FIELD)
	if info_label != null:
		info_label.visible = (_mode == Mode.CREATE_FIELD)
	if button_container != null:
		button_container.visible = (_mode == Mode.CREATE_FIELD)

	if _town_link_container != null:
		_town_link_container.visible = (_mode == Mode.LINK_TOWN)
		if _mode == Mode.LINK_TOWN:
			_update_town_gateway_options()


func _update_town_gateway_options() -> void:
	## Populate the town gateway dropdown.
	if _town_gateway_option == null:
		return

	_town_gateway_option.clear()

	for i: int in range(_town_gateways.size()):
		var gw_data: Dictionary = _town_gateways[i]
		var direction: String = DIRECTION_NAMES[i] if i < DIRECTION_NAMES.size() else "Gateway %d" % i
		var has_link: bool = gw_data.get("has_link", false)
		var linked_name: String = gw_data.get("linked_map_name", "")

		var label: String = direction
		if has_link and not linked_name.is_empty():
			label += " (linked to %s)" % linked_name
		elif has_link:
			label += " (in use)"
		else:
			label += " (available)"

		_town_gateway_option.add_item(label)

	if not _town_gateways.is_empty():
		_selected_town_gateway_id = 0
		_update_town_link_warning()


func _update_town_link_warning() -> void:
	## Show warning if selected town gateway already has a link.
	if _warning_label == null:
		return

	if _selected_town_gateway_id < 0 or _selected_town_gateway_id >= _town_gateways.size():
		_warning_label.visible = false
		return

	var gw_data: Dictionary = _town_gateways[_selected_town_gateway_id]
	var has_link: bool = gw_data.get("has_link", false)

	_warning_label.visible = has_link
	if has_link:
		var linked_name: String = gw_data.get("linked_map_name", "Unknown")
		if linked_name.is_empty():
			_warning_label.text = "Warning: This gateway already has a connection. It will be replaced."
		else:
			_warning_label.text = "Warning: This will replace the link to '%s'" % linked_name


func _on_mode_create_field_pressed() -> void:
	_mode = Mode.CREATE_FIELD
	_update_mode_visibility()


func _on_mode_link_town_pressed() -> void:
	_mode = Mode.LINK_TOWN
	_update_mode_visibility()


func _on_town_gateway_selected(index: int) -> void:
	if index >= 0 and index < _town_gateways.size():
		_selected_town_gateway_id = index
		_update_town_link_warning()


func _on_confirm_link_pressed() -> void:
	if _selected_town_gateway_id < 0:
		return

	visible = false
	UIManager.unregister_blocking_ui()
	town_link_requested.emit(_selected_town_gateway_id)
