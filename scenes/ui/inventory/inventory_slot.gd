class_name InventorySlot
extends Control
## Individual inventory slot that displays an item icon and quantity.
## Emits signals for click interactions.

## Emitted when slot is left-clicked
signal left_clicked(slot_index: int)

## Emitted when slot is right-clicked
signal right_clicked(slot_index: int)

## The slot index in the inventory (0-24)
@export var slot_index: int = 0

@onready var _background: Panel = $Background
@onready var _icon: TextureRect = $Icon
@onready var _quantity_label: Label = $QuantityLabel

var _item_id: StringName = &""
var _quantity: int = 0
var _is_highlighted: bool = false

# Style colors
const COLOR_EMPTY: Color = Color(0.15, 0.15, 0.15, 0.8)
const COLOR_FILLED: Color = Color(0.2, 0.2, 0.25, 0.9)
const COLOR_HIGHLIGHT: Color = Color(0.3, 0.35, 0.5, 1.0)


func _ready() -> void:
	_update_display()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.pressed:
			if mouse_event.button_index == MOUSE_BUTTON_LEFT:
				left_clicked.emit(slot_index)
				accept_event()
			elif mouse_event.button_index == MOUSE_BUTTON_RIGHT:
				right_clicked.emit(slot_index)
				accept_event()


## Set the item to display in this slot
func set_item(item_id: StringName, quantity: int) -> void:
	_item_id = item_id
	_quantity = quantity
	_update_display()


## Clear the slot display
func clear() -> void:
	_item_id = &""
	_quantity = 0
	_update_display()


## Set whether slot is highlighted (for hover/selection)
func set_highlighted(highlighted: bool) -> void:
	_is_highlighted = highlighted
	_update_background()


## Check if slot is empty
func is_empty() -> bool:
	return _item_id == &""


## Get the item id in this slot
func get_item_id() -> StringName:
	return _item_id


## Get the quantity in this slot
func get_quantity() -> int:
	return _quantity


func _update_display() -> void:
	_update_background()
	_update_icon()
	_update_quantity()


func _update_background() -> void:
	if _background == null:
		return

	var style: StyleBoxFlat = _background.get_theme_stylebox("panel").duplicate()
	if style is StyleBoxFlat:
		if _is_highlighted:
			style.bg_color = COLOR_HIGHLIGHT
		elif _item_id != &"":
			style.bg_color = COLOR_FILLED
		else:
			style.bg_color = COLOR_EMPTY
		_background.add_theme_stylebox_override("panel", style)


func _update_icon() -> void:
	if _icon == null:
		return

	if _item_id == &"":
		_icon.texture = null
		_icon.visible = false
		return

	var item_data: ItemData = InventoryManager.get_item_data(_item_id)
	if item_data != null and item_data.icon != null:
		_icon.texture = item_data.icon
		_icon.modulate = Color.WHITE
		_icon.visible = true
	else:
		# No icon - use a placeholder shape
		if item_data != null and item_data.is_glowing:
			# Glowing items (like pearls) show as a colored circle
			_icon.texture = _create_circle_texture(item_data.glow_color)
		else:
			# Non-glowing items show as a gray square
			_icon.texture = _create_square_texture(Color(0.6, 0.6, 0.7, 1.0))
		_icon.modulate = Color.WHITE
		_icon.visible = true


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


func _update_quantity() -> void:
	if _quantity_label == null:
		return

	if _quantity >= 1:
		_quantity_label.text = str(_quantity)
		_quantity_label.visible = true
	else:
		_quantity_label.text = ""
		_quantity_label.visible = false
