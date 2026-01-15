class_name Interactable
extends Area3D
## Base component for interactable objects. Add as child to any StaticBody3D/CharacterBody3D.
## Emits interacted signal when player presses interact while in range.

signal interacted(player: Node3D)

## The type of interaction (e.g., "Touch", "Open", "Read", "Use")
@export var interaction_type: String = "Touch"

## The name of this object shown in the prompt
@export var object_name: String = "Object"

## Collision shape radius for interaction detection
@export var interaction_radius: float = 2.0

## Height offset for the prompt label above the interactable
@export var prompt_height_offset: float = 2.0

var _prompt_label: Label3D = null


func _ready() -> void:
	_setup_collision()
	_setup_prompt_label()


func _setup_collision() -> void:
	# Create collision shape for interaction area
	var collision := CollisionShape3D.new()
	var sphere := SphereShape3D.new()
	sphere.radius = interaction_radius
	collision.shape = sphere
	add_child(collision)

	# Set collision layer 4 so player's interaction area (mask 4) can detect us
	collision_layer = 4
	collision_mask = 0  # We don't need to detect anything


func _setup_prompt_label() -> void:
	# Skip label creation in headless mode (CI testing) to avoid font errors
	if DisplayServer.get_name() == "headless":
		return

	_prompt_label = Label3D.new()
	_prompt_label.text = "%s the %s" % [interaction_type, object_name]
	_prompt_label.position = Vector3(0, prompt_height_offset, 0)
	_prompt_label.font_size = 48
	_prompt_label.outline_size = 12
	_prompt_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_prompt_label.visible = false
	add_child(_prompt_label)


## Show the interaction prompt (called by player when in range)
func show_prompt() -> void:
	if _prompt_label:
		_prompt_label.visible = true


## Hide the interaction prompt (called by player when leaving range)
func hide_prompt() -> void:
	if _prompt_label:
		_prompt_label.visible = false


## Called by the player when they interact with this object
func interact(player: Node3D) -> void:
	interacted.emit(player)
