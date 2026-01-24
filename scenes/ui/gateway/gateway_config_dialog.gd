class_name GatewayConfigDialog
extends Control
## Dialog for configuring gateway links by sacrificing a pearl.
## The pearl type determines the field's theme and visuals.

## Emitted when player confirms gateway configuration
signal gateway_configured(generation_seed: int, field_name: String, pearl_type: StringName)

## Emitted when dialog is cancelled
signal cancelled

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

@onready var _title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var _pearl_option: OptionButton = $Panel/VBoxContainer/PearlContainer/PearlOption
@onready var _no_pearls_label: Label = $Panel/VBoxContainer/PearlContainer/NoPearlsLabel
@onready var _create_button: Button = $Panel/VBoxContainer/ButtonContainer/CreateButton
@onready var _cancel_button: Button = $Panel/VBoxContainer/ButtonContainer/CancelButton

var _gateway_id: int = 0
var _gateway_direction: String = ""
var _available_pearls: Array[StringName] = []
var _selected_pearl_type: StringName = &""


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


func _consume_pearl(pearl_type: StringName) -> bool:
	## Find and remove one pearl from inventory. Returns true if successful.
	for i: int in range(InventoryManager.INVENTORY_SIZE):
		var slot: Dictionary = InventoryManager.get_slot(i)
		if not slot.is_empty():
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

	# Save the pearl type BEFORE consuming (consuming triggers inventory_changed which resets selection)
	var pearl_to_use: StringName = _selected_pearl_type

	# Consume the pearl from inventory
	if not _consume_pearl(pearl_to_use):
		push_warning("GatewayConfigDialog: Failed to consume pearl")
		return

	# Generate seed and name based on pearl type
	var seed_value: int = _generate_seed_from_pearl(pearl_to_use)
	var field_name: String = _get_field_name_for_pearl(pearl_to_use)

	visible = false
	gateway_configured.emit(seed_value, field_name, pearl_to_use)


func _on_cancel_button_pressed() -> void:
	_close()


func _on_inventory_changed() -> void:
	if visible:
		_update_pearl_options()
