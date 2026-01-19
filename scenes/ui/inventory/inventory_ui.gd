class_name InventoryUI
extends Control
## Main inventory panel with 5x5 grid of slots.
## Handles item pickup, placement, swapping, and merging.

## Emitted when inventory is closed
signal closed

## Emitted when player wants to drop an item
signal drop_requested(item_id: StringName, quantity: int)

enum State { CLOSED, IDLE, HOLDING, CONTEXT_MENU, SPLIT_DIALOG }

const GRID_SIZE: int = 5
const SLOT_COUNT: int = 25

@onready var _panel: Panel = $Panel
@onready var _grid: GridContainer = $Panel/MarginContainer/VBoxContainer/GridContainer
@onready var _close_button: Button = $Panel/MarginContainer/VBoxContainer/CloseButton
@onready var _held_item: HeldItem = $HeldItem
@onready var _context_menu: InventoryContextMenu = $ContextMenu
@onready var _split_dialog: SplitDialog = $SplitDialog

var _slots: Array[InventorySlot] = []
var _state: State = State.CLOSED

# Held item tracking
var _held_item_id: StringName = &""
var _held_quantity: int = 0
var _held_source_slot: int = -1
var _held_from_split: bool = false


# =============================================================================
# Dictionary Helper Functions
# =============================================================================

static func _get_item_id(slot_data: Dictionary) -> StringName:
	## Safely extract item_id from slot dictionary.
	## Note: @warning_ignore needed because GDScript doesn't track type narrowing from 'is' checks
	var value: Variant = slot_data.get("item_id", "")
	if value is StringName:
		@warning_ignore("unsafe_cast")
		return value as StringName
	if value is String:
		@warning_ignore("unsafe_cast")
		return StringName(value as String)
	return &""


static func _get_quantity(slot_data: Dictionary) -> int:
	## Safely extract quantity from slot dictionary.
	## Note: @warning_ignore needed because GDScript doesn't track type narrowing from 'is' checks
	var value: Variant = slot_data.get("quantity", 0)
	if value is int:
		@warning_ignore("unsafe_cast")
		return value as int
	if value is float:
		@warning_ignore("unsafe_cast")
		return int(value as float)
	return 0


func _ready() -> void:
	visible = false
	_state = State.CLOSED

	# Setup grid
	_setup_slots()

	# Connect signals
	@warning_ignore("return_value_discarded")
	_close_button.pressed.connect(_on_close_button_pressed)

	@warning_ignore("return_value_discarded")
	InventoryManager.inventory_changed.connect(_on_inventory_changed)

	@warning_ignore("return_value_discarded")
	InventoryManager.slot_updated.connect(_on_slot_updated)

	# Setup context menu
	if _context_menu != null:
		_context_menu.visible = false
		@warning_ignore("return_value_discarded")
		_context_menu.drop_requested.connect(_on_context_drop_requested)
		@warning_ignore("return_value_discarded")
		_context_menu.split_requested.connect(_on_context_split_requested)

	# Setup split dialog
	if _split_dialog != null:
		_split_dialog.visible = false
		@warning_ignore("return_value_discarded")
		_split_dialog.split_confirmed.connect(_on_split_confirmed)
		@warning_ignore("return_value_discarded")
		_split_dialog.cancelled.connect(_on_split_cancelled)


func _exit_tree() -> void:
	if InventoryManager.inventory_changed.is_connected(_on_inventory_changed):
		InventoryManager.inventory_changed.disconnect(_on_inventory_changed)
	if InventoryManager.slot_updated.is_connected(_on_slot_updated):
		InventoryManager.slot_updated.disconnect(_on_slot_updated)


func _input(event: InputEvent) -> void:
	if _state == State.CLOSED:
		return

	# Handle escape to close or cancel
	if event.is_action_pressed("ui_cancel"):
		match _state:
			State.HOLDING:
				_return_held_to_source()
				_state = State.IDLE
			State.CONTEXT_MENU:
				_hide_context_menu()
				_state = State.IDLE
			State.SPLIT_DIALOG:
				_hide_split_dialog()
				_state = State.IDLE
			State.IDLE:
				hide_inventory()
		get_viewport().set_input_as_handled()

	# Handle click outside inventory when holding
	if _state == State.HOLDING and event is InputEventMouseButton:
		var mouse_event: InputEventMouseButton = event
		if mouse_event.pressed and mouse_event.button_index == MOUSE_BUTTON_LEFT:
			# Check if click is outside the panel
			if not _panel.get_global_rect().has_point(mouse_event.position):
				_drop_held_item()
				get_viewport().set_input_as_handled()


func _setup_slots() -> void:
	_slots.clear()

	# Instantiate slot scenes
	var slot_scene: PackedScene = preload("res://scenes/ui/inventory/inventory_slot.tscn")

	for i: int in range(SLOT_COUNT):
		var slot: InventorySlot = slot_scene.instantiate()
		slot.slot_index = i
		_grid.add_child(slot)
		_slots.append(slot)

		@warning_ignore("return_value_discarded")
		slot.left_clicked.connect(_on_slot_left_clicked)
		@warning_ignore("return_value_discarded")
		slot.right_clicked.connect(_on_slot_right_clicked)


func _refresh_all_slots() -> void:
	for i: int in range(SLOT_COUNT):
		_refresh_slot(i)


func _refresh_slot(index: int) -> void:
	if index < 0 or index >= _slots.size():
		return

	var slot_data: Dictionary = InventoryManager.get_slot(index)
	var slot: InventorySlot = _slots[index]

	if slot_data.is_empty():
		slot.clear()
	else:
		slot.set_item(_get_item_id(slot_data), _get_quantity(slot_data))


# =============================================================================
# Show/Hide
# =============================================================================

func show_inventory() -> void:
	if _state != State.CLOSED:
		return

	_refresh_all_slots()
	visible = true
	_state = State.IDLE

	# Show cursor
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_inventory() -> void:
	if _state == State.CLOSED:
		return

	# Return held item to source if holding
	if _state == State.HOLDING:
		_return_held_to_source()

	# Hide submenus
	_hide_context_menu()
	_hide_split_dialog()

	visible = false
	_state = State.CLOSED
	closed.emit()


func toggle_inventory() -> void:
	if _state == State.CLOSED:
		show_inventory()
	else:
		hide_inventory()


func is_open() -> bool:
	return _state != State.CLOSED


# =============================================================================
# Slot Interaction Handlers
# =============================================================================

func _on_slot_left_clicked(slot_index: int) -> void:
	match _state:
		State.IDLE:
			_try_pickup_from_slot(slot_index)
		State.HOLDING:
			_try_place_into_slot(slot_index)
		State.CONTEXT_MENU:
			_hide_context_menu()
			_state = State.IDLE
		State.SPLIT_DIALOG:
			pass  # Ignore clicks while split dialog is open


func _on_slot_right_clicked(slot_index: int) -> void:
	match _state:
		State.IDLE:
			_show_context_menu(slot_index)
		State.HOLDING:
			pass  # Could implement right-click while holding if needed
		State.CONTEXT_MENU:
			_hide_context_menu()
			_show_context_menu(slot_index)
		State.SPLIT_DIALOG:
			pass


func _try_pickup_from_slot(slot_index: int) -> void:
	var slot_data: Dictionary = InventoryManager.get_slot(slot_index)
	if slot_data.is_empty():
		return

	# Pick up the item
	_held_item_id = _get_item_id(slot_data)
	_held_quantity = _get_quantity(slot_data)
	_held_source_slot = slot_index
	_held_from_split = false

	# Clear the slot visually (but don't modify InventoryManager yet)
	_slots[slot_index].clear()

	# Show held item on cursor
	_held_item.set_item(_held_item_id, _held_quantity)

	_state = State.HOLDING


func _try_place_into_slot(slot_index: int) -> void:
	if not _held_item.is_holding():
		return

	var target_slot_data: Dictionary = InventoryManager.get_slot(slot_index)

	if target_slot_data.is_empty():
		# Place into empty slot
		_place_held_into_slot(slot_index)
	elif _get_item_id(target_slot_data) == _held_item_id:
		# Try to merge stacks
		_merge_held_into_slot(slot_index)
	else:
		# Swap with different item
		_swap_held_with_slot(slot_index)


func _place_held_into_slot(slot_index: int) -> void:
	# Clear source slot in manager (only if valid source and not from split)
	if not _held_from_split and _held_source_slot >= 0:
		InventoryManager.clear_slot(_held_source_slot)

	# Set target slot
	InventoryManager.set_slot(slot_index, _held_item_id, _held_quantity)

	_clear_held_state()
	_state = State.IDLE


func _merge_held_into_slot(slot_index: int) -> void:
	var target_data: Dictionary = InventoryManager.get_slot(slot_index)
	var item_data: ItemData = InventoryManager.get_item_data(_held_item_id)

	if item_data == null:
		return

	var max_stack: int = item_data.max_stack
	var target_quantity: int = _get_quantity(target_data)
	var total: int = target_quantity + _held_quantity

	if total <= max_stack:
		# All items fit
		if not _held_from_split and _held_source_slot >= 0:
			InventoryManager.clear_slot(_held_source_slot)
		InventoryManager.set_slot(slot_index, _held_item_id, total)
		_clear_held_state()
		_state = State.IDLE
	else:
		# Overflow - keep holding remainder
		var overflow: int = total - max_stack
		if not _held_from_split and _held_source_slot >= 0:
			InventoryManager.clear_slot(_held_source_slot)
		InventoryManager.set_slot(slot_index, _held_item_id, max_stack)

		_held_quantity = overflow
		_held_source_slot = -1  # Source is fully consumed, no valid source for overflow
		_held_item.set_item(_held_item_id, _held_quantity)
		# Stay in HOLDING state with overflow


func _swap_held_with_slot(slot_index: int) -> void:
	var target_data: Dictionary = InventoryManager.get_slot(slot_index)

	# Extract target slot values
	var target_item_id: StringName = _get_item_id(target_data)
	var target_quantity: int = _get_quantity(target_data)

	if _held_from_split or _held_source_slot < 0:
		# Source slot has other items or no valid source - place held in target, pick up target's items
		InventoryManager.set_slot(slot_index, _held_item_id, _held_quantity)

		# Now hold the swapped item (no valid source to return to)
		_held_item_id = target_item_id
		_held_quantity = target_quantity
		_held_source_slot = -1
		_held_from_split = false
		_held_item.set_item(_held_item_id, _held_quantity)
		# Stay in HOLDING state
	else:
		# Source slot is empty - complete the swap and stop holding
		InventoryManager.set_slot(_held_source_slot, target_item_id, target_quantity)
		InventoryManager.set_slot(slot_index, _held_item_id, _held_quantity)

		_clear_held_state()
		_state = State.IDLE


func _return_held_to_source() -> void:
	if not _held_item.is_holding():
		return

	if _held_source_slot < 0:
		# No valid source (e.g., after swap or overflow) - add to inventory
		var overflow: int = InventoryManager.add_item(_held_item_id, _held_quantity)
		if overflow > 0:
			# Couldn't fit all items, drop the rest
			drop_requested.emit(_held_item_id, overflow)
	elif _held_from_split:
		# Add split items back to source slot
		var source_data: Dictionary = InventoryManager.get_slot(_held_source_slot)
		var source_quantity: int = _get_quantity(source_data)
		InventoryManager.set_slot(_held_source_slot, _held_item_id, source_quantity + _held_quantity)
	else:
		# Return full stack to source slot
		InventoryManager.set_slot(_held_source_slot, _held_item_id, _held_quantity)

	_clear_held_state()


func _drop_held_item() -> void:
	if not _held_item.is_holding():
		return

	# Clear source slot in manager (only if valid source and not from split)
	if not _held_from_split and _held_source_slot >= 0:
		InventoryManager.clear_slot(_held_source_slot)

	# Emit drop request
	drop_requested.emit(_held_item_id, _held_quantity)

	_clear_held_state()
	_state = State.IDLE


func _clear_held_state() -> void:
	_held_item_id = &""
	_held_quantity = 0
	_held_source_slot = -1
	_held_from_split = false
	_held_item.clear()


# =============================================================================
# Context Menu
# =============================================================================

func _show_context_menu(slot_index: int) -> void:
	var slot_data: Dictionary = InventoryManager.get_slot(slot_index)
	if slot_data.is_empty():
		return

	if _context_menu != null:
		var item_data: ItemData = InventoryManager.get_item_data(_get_item_id(slot_data))
		_context_menu.show_for_slot(slot_index, item_data, _get_quantity(slot_data))
		_state = State.CONTEXT_MENU


func _hide_context_menu() -> void:
	if _context_menu != null:
		_context_menu.visible = false


func _on_context_drop_requested(slot_index: int) -> void:
	_hide_context_menu()

	var slot_data: Dictionary = InventoryManager.get_slot(slot_index)
	if slot_data.is_empty():
		_state = State.IDLE
		return

	# Drop entire stack
	InventoryManager.clear_slot(slot_index)
	drop_requested.emit(_get_item_id(slot_data), _get_quantity(slot_data))

	_state = State.IDLE


func _on_context_split_requested(slot_index: int) -> void:
	_hide_context_menu()

	var slot_data: Dictionary = InventoryManager.get_slot(slot_index)
	var quantity: int = _get_quantity(slot_data)
	if slot_data.is_empty() or quantity <= 1:
		_state = State.IDLE
		return

	_show_split_dialog(slot_index, quantity)


# =============================================================================
# Split Dialog
# =============================================================================

func _show_split_dialog(slot_index: int, max_quantity: int) -> void:
	if _split_dialog != null:
		_split_dialog.show_for_slot(slot_index, max_quantity)
		_state = State.SPLIT_DIALOG


func _hide_split_dialog() -> void:
	if _split_dialog != null:
		_split_dialog.visible = false


func _on_split_confirmed(slot_index: int, split_quantity: int) -> void:
	_hide_split_dialog()

	var slot_data: Dictionary = InventoryManager.get_slot(slot_index)
	if slot_data.is_empty() or split_quantity <= 0:
		_state = State.IDLE
		return

	# Extract slot values
	var slot_item_id: StringName = _get_item_id(slot_data)
	var slot_quantity: int = _get_quantity(slot_data)

	if split_quantity >= slot_quantity:
		_state = State.IDLE
		return

	# Reduce source slot
	var remaining: int = slot_quantity - split_quantity
	InventoryManager.set_slot(slot_index, slot_item_id, remaining)

	# Pick up split amount
	_held_item_id = slot_item_id
	_held_quantity = split_quantity
	_held_source_slot = slot_index
	_held_from_split = true
	_held_item.set_item(_held_item_id, _held_quantity)

	_state = State.HOLDING


func _on_split_cancelled() -> void:
	_hide_split_dialog()
	_state = State.IDLE


# =============================================================================
# Event Handlers
# =============================================================================

func _on_close_button_pressed() -> void:
	hide_inventory()


func _on_inventory_changed() -> void:
	if _state != State.CLOSED:
		_refresh_all_slots()


func _on_slot_updated(slot_index: int) -> void:
	if _state != State.CLOSED:
		_refresh_slot(slot_index)
