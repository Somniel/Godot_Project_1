class_name SplitDialog
extends Control
## Dialog for splitting a stack of items.
## Shows a slider to select how many to split off.

## Emitted when split is confirmed with quantity
signal split_confirmed(slot_index: int, quantity: int)

## Emitted when dialog is cancelled
signal cancelled

@onready var _panel: Panel = $Panel
@onready var _slider: HSlider = $Panel/VBoxContainer/HSlider
@onready var _quantity_label: Label = $Panel/VBoxContainer/QuantityLabel
@onready var _confirm_button: Button = $Panel/VBoxContainer/HBoxContainer/ConfirmButton
@onready var _cancel_button: Button = $Panel/VBoxContainer/HBoxContainer/CancelButton

var _current_slot: int = -1
var _max_quantity: int = 1


func _ready() -> void:
	visible = false

	@warning_ignore("return_value_discarded")
	_slider.value_changed.connect(_on_slider_changed)
	@warning_ignore("return_value_discarded")
	_confirm_button.pressed.connect(_on_confirm_pressed)
	@warning_ignore("return_value_discarded")
	_cancel_button.pressed.connect(_on_cancel_pressed)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	# Close on escape
	if event.is_action_pressed("ui_cancel"):
		_on_cancel_pressed()
		get_viewport().set_input_as_handled()


## Show the split dialog for a slot with given max quantity
func show_for_slot(slot_index: int, max_quantity: int) -> void:
	_current_slot = slot_index
	_max_quantity = max_quantity

	# Configure slider (1 to max-1, since we need at least 1 in original)
	_slider.min_value = 1
	_slider.max_value = max_quantity - 1
	_slider.value = 1
	_slider.step = 1

	_update_quantity_label()

	# Center on screen
	var viewport_size: Vector2 = get_viewport().get_visible_rect().size
	global_position = (viewport_size - _panel.size) / 2

	visible = true


func _update_quantity_label() -> void:
	var split_amount: int = int(_slider.value)
	var remaining: int = _max_quantity - split_amount
	_quantity_label.text = "Split: %d / Keep: %d" % [split_amount, remaining]


func _on_slider_changed(_value: float) -> void:
	_update_quantity_label()


func _on_confirm_pressed() -> void:
	var split_amount: int = int(_slider.value)
	visible = false
	split_confirmed.emit(_current_slot, split_amount)


func _on_cancel_pressed() -> void:
	visible = false
	cancelled.emit()
