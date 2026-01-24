class_name TravelConfirmDialog
extends Control
## Confirmation dialog shown when a player tries to travel through a gateway.
## Displays the destination name and asks for confirmation.

signal confirmed
signal cancelled

@onready var _title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var _message_label: Label = $Panel/VBoxContainer/MessageLabel
@onready var _confirm_button: Button = $Panel/VBoxContainer/ButtonContainer/ConfirmButton
@onready var _cancel_button: Button = $Panel/VBoxContainer/ButtonContainer/CancelButton

var _pending_destination_lobby_id: int = 0


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


## Show the confirmation dialog for traveling to a destination
func show_dialog(destination_name: String, destination_lobby_id: int) -> void:
	_pending_destination_lobby_id = destination_lobby_id

	var display_name: String = destination_name if not destination_name.is_empty() else "Unknown"
	_title_label.text = "Travel to %s?" % display_name
	_message_label.text = "Are you sure you want to travel to this location?"

	visible = true
	_cancel_button.grab_focus()


## Get the pending destination lobby ID
func get_destination_lobby_id() -> int:
	return _pending_destination_lobby_id


func _close() -> void:
	visible = false
	_pending_destination_lobby_id = 0
	cancelled.emit()


func _on_confirm_pressed() -> void:
	visible = false
	confirmed.emit()


func _on_cancel_pressed() -> void:
	_close()
