class_name WorldItem
extends StaticBody3D
## Base class for items that exist in the game world and can be picked up.
## Floats above ground and emits picked_up signal when interacted with.

## Emitted when a player picks up this item
signal picked_up(player: Node3D)

## The item type identifier
@export var item_id: StringName = &""

## How many items this world item represents
@export var quantity: int = 1

## Float height above ground
@export var float_height: float = 0.3

## Float bob amplitude (how far up/down it bobs)
@export var bob_amplitude: float = 0.1

## Float bob speed (cycles per second)
@export var bob_speed: float = 1.0

## Rotation speed (degrees per second)
@export var rotation_speed: float = 45.0

@onready var _interactable: Interactable = $Interactable
@onready var _glow_light: OmniLight3D = $OmniLight3D

var _base_y: float = 0.0
var _time: float = 0.0
var _item_data: ItemData = null


func _ready() -> void:
	_base_y = position.y + float_height
	position.y = _base_y

	# Connect interactable signal
	if _interactable != null:
		@warning_ignore("return_value_discarded")
		_interactable.interacted.connect(_on_interacted)

	# Load item data and configure
	_load_item_data()
	_configure_from_item_data()

	# Ensure no player collision
	collision_layer = 0
	collision_mask = 1  # Only collide with world geometry for ground support


func _process(delta: float) -> void:
	_time += delta

	# Bob up and down
	var bob_offset: float = sin(_time * bob_speed * TAU) * bob_amplitude
	position.y = _base_y + bob_offset

	# Rotate slowly
	rotate_y(deg_to_rad(rotation_speed * delta))


func _load_item_data() -> void:
	if item_id == &"":
		return
	_item_data = InventoryManager.get_item_data(item_id)


func _configure_from_item_data() -> void:
	if _item_data == null:
		return

	# Configure interactable
	if _interactable != null:
		_interactable.interaction_type = _item_data.interaction_type
		_interactable.object_name = _get_display_name()

	# Configure glow
	if _glow_light != null:
		_glow_light.visible = _item_data.is_glowing
		if _item_data.is_glowing:
			_glow_light.light_color = _item_data.glow_color
			_glow_light.light_energy = _item_data.glow_energy
			_glow_light.omni_range = _item_data.glow_range


func _get_display_name() -> String:
	if _item_data == null:
		return "Item"

	if quantity > 1:
		return "%s (%d)" % [_item_data.display_name, quantity]
	return _item_data.display_name


func _on_interacted(player: Node3D) -> void:
	picked_up.emit(player)


## Set the item data for this world item
func set_item(new_item_id: StringName, new_quantity: int = 1) -> void:
	item_id = new_item_id
	quantity = new_quantity
	_load_item_data()
	_configure_from_item_data()


## Get the item data resource
func get_item_data() -> ItemData:
	return _item_data


## Update the quantity and refresh display
func set_quantity(new_quantity: int) -> void:
	quantity = new_quantity
	if _interactable != null and _item_data != null:
		_interactable.object_name = _get_display_name()
