class_name InventoryContextMenu
extends Control
## Right-click context menu for inventory slots.
## Shows Drop and Split options.

## Emitted when Drop is selected
signal drop_requested(slot_index: int)

## Emitted when Split is selected
signal split_requested(slot_index: int)

@onready var _panel: Panel = $Panel
@onready var _drop_button: Button = $Panel/VBoxContainer/DropButton
@onready var _split_button: Button = $Panel/VBoxContainer/SplitButton

var _current_slot: int = -1


func _ready() -> void:
	visible = false

	@warning_ignore("return_value_discarded")
	_drop_button.pressed.connect(_on_drop_pressed)
	@warning_ignore("return_value_discarded")
	_split_button.pressed.connect(_on_split_pressed)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Close on click outside
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.pressed:
			if not _panel.get_global_rect().has_point(mouse_event.position):
				visible = false
				get_viewport().set_input_as_handled()


## Show the context menu for a specific slot
func show_for_slot(slot_index: int, _item_data: ItemData, quantity: int) -> void:
	_current_slot = slot_index

	# Show/hide split button based on quantity
	_split_button.visible = quantity > 1

	# Position near cursor
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	global_position = mouse_pos + Vector2(4, 4)

	# Clamp to screen bounds
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	var menu_size: Vector2 = _panel.size

	if global_position.x + menu_size.x > viewport_size.x:
		global_position.x = viewport_size.x - menu_size.x - 4
	if global_position.y + menu_size.y > viewport_size.y:
		global_position.y = viewport_size.y - menu_size.y - 4

	visible = true


func _on_drop_pressed() -> void:
	visible = false
	drop_requested.emit(_current_slot)


func _on_split_pressed() -> void:
	visible = false
	split_requested.emit(_current_slot)
