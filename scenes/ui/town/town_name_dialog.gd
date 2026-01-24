class_name TownNameDialog
extends Control
## Dialog for naming a new town or editing an existing town name.

signal name_confirmed(town_name: String)
signal cancelled

@onready var _title_label: Label = $Panel/VBoxContainer/TitleLabel
@onready var _name_input: LineEdit = $Panel/VBoxContainer/NameInput
@onready var _confirm_button: Button = $Panel/VBoxContainer/ButtonContainer/ConfirmButton
@onready var _cancel_button: Button = $Panel/VBoxContainer/ButtonContainer/CancelButton

var _is_new_town: bool = true
var _allow_cancel: bool = true


func _ready() -> void:
	visible = false
	@warning_ignore("return_value_discarded")
	_confirm_button.pressed.connect(_on_confirm_pressed)
	@warning_ignore("return_value_discarded")
	_cancel_button.pressed.connect(_on_cancel_pressed)
	@warning_ignore("return_value_discarded")
	_name_input.text_changed.connect(_on_name_changed)
	@warning_ignore("return_value_discarded")
	_name_input.text_submitted.connect(_on_name_submitted)


func _input(event: InputEvent) -> void:
	if not visible:
		return

	if event.is_action_pressed("ui_cancel") and _allow_cancel:
		_close()
		get_viewport().set_input_as_handled()


## Show dialog for naming a new town
func show_for_new_town() -> void:
	_is_new_town = true
	_allow_cancel = false
	_title_label.text = "Name Your Town"
	_name_input.text = "%s's Town" % SteamManager.get_steam_username()
	_cancel_button.visible = false
	_validate_input()
	visible = true
	_name_input.grab_focus()
	_name_input.select_all()


## Show dialog for editing existing town name
func show_for_edit(current_name: String) -> void:
	_is_new_town = false
	_allow_cancel = true
	_title_label.text = "Rename Town"
	_name_input.text = current_name
	_cancel_button.visible = true
	_validate_input()
	visible = true
	_name_input.grab_focus()
	_name_input.select_all()


func _validate_input() -> void:
	var name_valid: bool = not _name_input.text.strip_edges().is_empty()
	_confirm_button.disabled = not name_valid


func _close() -> void:
	visible = false
	cancelled.emit()


func _on_confirm_pressed() -> void:
	var town_name: String = _name_input.text.strip_edges()
	if town_name.is_empty():
		return
	visible = false
	name_confirmed.emit(town_name)


func _on_cancel_pressed() -> void:
	_close()


func _on_name_changed(_text: String) -> void:
	_validate_input()


func _on_name_submitted(_text: String) -> void:
	if not _confirm_button.disabled:
		_on_confirm_pressed()
