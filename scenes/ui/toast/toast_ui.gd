class_name ToastUI
extends Control
## Displays toast notification messages with fade animation.
## Shows messages like "Inventory Full" briefly on screen.

@export var display_duration: float = 2.0
@export var fade_duration: float = 0.3

@onready var _label: Label = $Panel/MarginContainer/Label
@onready var _audio_player: AudioStreamPlayer = $AudioPlayer

var _tween: Tween = null


func _ready() -> void:
	visible = false
	modulate.a = 0.0


## Show a toast message
func show_toast(message: String) -> void:
	_label.text = message

	# Cancel any existing animation
	if _tween != null and _tween.is_valid():
		_tween.kill()

	# Reset and show
	visible = true
	modulate.a = 0.0

	# Play sound
	if _audio_player != null and _audio_player.stream != null:
		_audio_player.play()

	# Animate
	_tween = create_tween()
	@warning_ignore("return_value_discarded")
	_tween.tween_property(self, "modulate:a", 1.0, fade_duration)
	@warning_ignore("return_value_discarded")
	_tween.tween_interval(display_duration)
	@warning_ignore("return_value_discarded")
	_tween.tween_property(self, "modulate:a", 0.0, fade_duration)
	@warning_ignore("return_value_discarded")
	_tween.tween_callback(_on_fade_complete)


func _on_fade_complete() -> void:
	visible = false
