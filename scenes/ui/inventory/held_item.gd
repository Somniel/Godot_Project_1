class_name HeldItem
extends Control
## Displays an item icon that follows the cursor when holding an item.

@onready var _icon: TextureRect = $Icon
@onready var _quantity_label: Label = $QuantityLabel

var _item_id: StringName = &""
var _quantity: int = 0

## Offset from cursor position (so item appears "carried" below cursor)
const CURSOR_OFFSET: Vector2 = Vector2(8, 8)


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE


func _process(_delta: float) -> void:
	if visible:
		global_position = get_viewport().get_mouse_position() + CURSOR_OFFSET


## Set the item being held
func set_item(item_id: StringName, quantity: int) -> void:
	_item_id = item_id
	_quantity = quantity

	var item_data: ItemData = InventoryManager.get_item_data(item_id)
	if item_data != null and item_data.icon != null:
		_icon.texture = item_data.icon
		_icon.modulate = Color.WHITE
	elif item_data != null and item_data.is_glowing:
		# Glowing items show as a colored circle
		_icon.texture = _create_circle_texture(item_data.glow_color)
		_icon.modulate = Color.WHITE
	else:
		# Non-glowing items show as a gray square
		_icon.texture = _create_square_texture(Color(0.6, 0.6, 0.7, 1.0))
		_icon.modulate = Color.WHITE

	_quantity_label.text = str(quantity)
	_quantity_label.visible = true

	visible = true


## Clear the held item
func clear() -> void:
	_item_id = &""
	_quantity = 0
	_icon.texture = null
	_quantity_label.visible = false
	visible = false


## Check if currently holding an item
func is_holding() -> bool:
	return _item_id != &""


## Get the held item id
func get_item_id() -> StringName:
	return _item_id


## Get the held quantity
func get_quantity() -> int:
	return _quantity


func _create_square_texture(color: Color) -> ImageTexture:
	# Create a simple colored square texture as placeholder
	var image: Image = Image.create(32, 32, false, Image.FORMAT_RGBA8)
	image.fill(color)
	return ImageTexture.create_from_image(image)


func _create_circle_texture(color: Color) -> ImageTexture:
	# Create a colored circle texture for glowing items
	var tex_size: int = 32
	var center: float = tex_size / 2.0
	var radius: float = center - 2.0  # Small margin
	var image: Image = Image.create(tex_size, tex_size, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)

	for y: int in range(tex_size):
		for x: int in range(tex_size):
			var dist: float = Vector2(x - center, y - center).length()
			if dist <= radius:
				# Soft edge for anti-aliasing
				var alpha: float = clampf(1.0 - (dist - radius + 1.0), 0.0, 1.0)
				var pixel_color: Color = color
				pixel_color.a = alpha
				image.set_pixel(x, y, pixel_color)

	return ImageTexture.create_from_image(image)
