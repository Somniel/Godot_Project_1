class_name HostTravelWarning
extends Control
## Warning dialog shown when the town host tries to travel away.
## Warns that the town will be unjoinable while they're away.

signal confirmed
signal cancelled

@onready var _confirm_button: Button = $Panel/VBoxContainer/ButtonContainer/ConfirmButton
@onready var _cancel_button: Button = $Panel/VBoxContainer/ButtonContainer/CancelButton


func _ready() -> void:
	visible = false
	@warning_ignore("return_value_discarded")
	_confirm_button.pressed.connect(_on_confirm_pressed)
	@warning_ignore("return_value_discarded")
	_cancel_button.pressed.connect(_on_cancel_pressed)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel"):
		_close()
		get_viewport().set_input_as_handled()


## Show the warning dialog
func show_warning() -> void:
	visible = true
	_cancel_button.grab_focus()


func _close() -> void:
	visible = false
	cancelled.emit()


func _on_confirm_pressed() -> void:
	visible = false
	confirmed.emit()


func _on_cancel_pressed() -> void:
	_close()
