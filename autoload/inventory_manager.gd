extends Node
## Manages player inventory state and provides methods for item manipulation.
## Delegates persistence to an InventoryStorage implementation.

const INVENTORY_SIZE: int = 25

## Emitted when any slot changes
signal inventory_changed

## Emitted when a specific slot changes
signal slot_updated(slot_index: int)

## Emitted when an item is added to inventory
signal item_added(item_id: StringName, quantity: int)

## Emitted when an item is removed from inventory
signal item_removed(item_id: StringName, quantity: int)

## Emitted when inventory is full and item cannot be added
signal inventory_full

## Emitted after inventory is loaded from storage
signal inventory_loaded

## Emitted after inventory is saved to storage
signal inventory_saved

## Slot data: Array of Dictionaries with {item_id: StringName, quantity: int}
## Empty slots are empty dictionaries {}
var _slots: Array[Dictionary] = []

## Registry of item definitions by id
var _item_registry: Dictionary = {}

## Whether inventory has been loaded
var _is_loaded: bool = false

## Storage backend for persistence
var _storage: InventoryStorage = null


# =============================================================================
# Dictionary Helper Functions
# =============================================================================

static func get_slot_item_id(slot: Dictionary) -> StringName:
	## Safely extract item_id from slot dictionary.
	var value: Variant = slot.get("item_id", "")
	if value is StringName:
		@warning_ignore("unsafe_cast")
		return value as StringName
	if value is String:
		@warning_ignore("unsafe_cast")
		return StringName(value as String)
	return &""


static func _get_slot_quantity(slot: Dictionary) -> int:
	## Safely extract quantity from slot dictionary.
	var value: Variant = slot.get("quantity", 0)
	if value is int:
		@warning_ignore("unsafe_cast")
		return value as int
	if value is float:
		@warning_ignore("unsafe_cast")
		return int(value as float)
	return 0


# =============================================================================
# Lifecycle
# =============================================================================

func _ready() -> void:
	_initialize_empty_inventory()
	_register_builtin_items()
	_setup_storage()


func _exit_tree() -> void:
	if _storage != null:
		_storage.flush()

	if SteamManager.steam_initialized.is_connected(_on_steam_initialized):
		SteamManager.steam_initialized.disconnect(_on_steam_initialized)


func _initialize_empty_inventory() -> void:
	_slots.clear()
	for i: int in range(INVENTORY_SIZE):
		_slots.append({})


func _setup_storage() -> void:
	# Create storage backend - swap this line to change implementations
	_storage = SteamCloudStorage.new()
	_storage.setup(self)

	@warning_ignore("return_value_discarded")
	_storage.load_completed.connect(_on_storage_load_completed)
	@warning_ignore("return_value_discarded")
	_storage.save_completed.connect(_on_storage_save_completed)

	@warning_ignore("return_value_discarded")
	SteamManager.steam_initialized.connect(_on_steam_initialized)

	if SteamManager.is_steam_initialized:
		_storage.load_inventory()


func _register_builtin_items() -> void:
	# Register air pearl item
	var air_pearl_path: String = "res://resources/items/air_pearl.tres"
	if ResourceLoader.exists(air_pearl_path):
		var air_pearl: ItemData = load(air_pearl_path)
		if air_pearl != null:
			register_item(air_pearl)

	# Register flame pearl item
	var flame_pearl_path: String = "res://resources/items/flame_pearl.tres"
	if ResourceLoader.exists(flame_pearl_path):
		var flame_pearl: ItemData = load(flame_pearl_path)
		if flame_pearl != null:
			register_item(flame_pearl)

	# Register life pearl item
	var life_pearl_path: String = "res://resources/items/life_pearl.tres"
	if ResourceLoader.exists(life_pearl_path):
		var life_pearl: ItemData = load(life_pearl_path)
		if life_pearl != null:
			register_item(life_pearl)

	# Register water pearl item
	var water_pearl_path: String = "res://resources/items/water_pearl.tres"
	if ResourceLoader.exists(water_pearl_path):
		var water_pearl: ItemData = load(water_pearl_path)
		if water_pearl != null:
			register_item(water_pearl)


func _on_steam_initialized() -> void:
	if _storage != null:
		_storage.load_inventory()


func _on_storage_load_completed(success: bool) -> void:
	if success and _storage != null:
		_slots = _storage.get_slots()
	_is_loaded = true
	inventory_changed.emit()
	inventory_loaded.emit()


func _on_storage_save_completed(_success: bool) -> void:
	inventory_saved.emit()


func _queue_save() -> void:
	if _storage != null:
		_storage.save_inventory(_slots)


# =============================================================================
# Item Registry
# =============================================================================

## Register an item definition for use in inventory
func register_item(data: ItemData) -> void:
	if data == null or data.id == &"":
		push_warning("InventoryManager: Cannot register null or unnamed item")
		return
	_item_registry[data.id] = data


## Get item data by id, returns null if not found
func get_item_data(item_id: StringName) -> ItemData:
	return _item_registry.get(item_id, null)


# =============================================================================
# Slot Access
# =============================================================================

## Get slot data at index. Returns {item_id, quantity} or empty dict
func get_slot(index: int) -> Dictionary:
	if index < 0 or index >= INVENTORY_SIZE:
		return {}
	return _slots[index].duplicate()


## Set slot contents directly
func set_slot(index: int, item_id: StringName, quantity: int) -> void:
	if index < 0 or index >= INVENTORY_SIZE:
		return

	if quantity <= 0 or item_id == &"":
		_slots[index] = {}
	else:
		_slots[index] = {"item_id": item_id, "quantity": quantity}

	slot_updated.emit(index)
	inventory_changed.emit()
	_queue_save()


## Clear a slot
func clear_slot(index: int) -> void:
	if index < 0 or index >= INVENTORY_SIZE:
		return

	_slots[index] = {}
	slot_updated.emit(index)
	inventory_changed.emit()
	_queue_save()


## Check if slot is empty
func is_slot_empty(index: int) -> bool:
	if index < 0 or index >= INVENTORY_SIZE:
		return true
	return _slots[index].is_empty()


## Find first empty slot, returns -1 if none
func find_empty_slot() -> int:
	for i: int in range(INVENTORY_SIZE):
		if _slots[i].is_empty():
			return i
	return -1


## Find slot containing item with space for more, returns -1 if none
func find_slot_with_space(item_id: StringName) -> int:
	var item_data: ItemData = get_item_data(item_id)
	if item_data == null:
		return -1

	for i: int in range(INVENTORY_SIZE):
		var slot: Dictionary = _slots[i]
		if not slot.is_empty() and get_slot_item_id(slot) == item_id:
			if _get_slot_quantity(slot) < item_data.max_stack:
				return i
	return -1


# =============================================================================
# Item Manipulation
# =============================================================================

## Add item to inventory. Returns overflow quantity (0 if all added)
func add_item(item_id: StringName, quantity: int = 1) -> int:
	if quantity <= 0:
		return 0

	var item_data: ItemData = get_item_data(item_id)
	if item_data == null:
		push_warning("InventoryManager: Unknown item '%s'" % item_id)
		return quantity

	var remaining: int = quantity

	# First try to stack with existing items
	while remaining > 0:
		var slot_idx: int = find_slot_with_space(item_id)
		if slot_idx == -1:
			break

		var slot: Dictionary = _slots[slot_idx]
		var can_add: int = item_data.max_stack - _get_slot_quantity(slot)
		var to_add: int = mini(remaining, can_add)

		_slots[slot_idx].quantity += to_add
		remaining -= to_add
		slot_updated.emit(slot_idx)

	# Then try to use empty slots
	while remaining > 0:
		var slot_idx: int = find_empty_slot()
		if slot_idx == -1:
			break

		var to_add: int = mini(remaining, item_data.max_stack)
		_slots[slot_idx] = {"item_id": item_id, "quantity": to_add}
		remaining -= to_add
		slot_updated.emit(slot_idx)

	if remaining < quantity:
		var added: int = quantity - remaining
		item_added.emit(item_id, added)
		inventory_changed.emit()
		_queue_save()

	if remaining > 0:
		inventory_full.emit()

	return remaining


## Remove quantity from a specific slot. Returns true if successful
func remove_from_slot(slot_index: int, quantity: int = 1) -> bool:
	if slot_index < 0 or slot_index >= INVENTORY_SIZE:
		return false

	var slot: Dictionary = _slots[slot_index]
	if slot.is_empty():
		return false

	var current_quantity: int = _get_slot_quantity(slot)
	if current_quantity < quantity:
		return false

	var item_id: StringName = get_slot_item_id(slot)
	var new_quantity: int = current_quantity - quantity

	if new_quantity <= 0:
		_slots[slot_index] = {}
	else:
		_slots[slot_index] = {"item_id": item_id, "quantity": new_quantity}

	item_removed.emit(item_id, quantity)
	slot_updated.emit(slot_index)
	inventory_changed.emit()
	_queue_save()
	return true


## Check if inventory has at least quantity of item
func has_item(item_id: StringName, quantity: int = 1) -> bool:
	return get_item_count(item_id) >= quantity


## Get total count of item across all slots
func get_item_count(item_id: StringName) -> int:
	var total: int = 0
	for slot: Dictionary in _slots:
		if not slot.is_empty() and get_slot_item_id(slot) == item_id:
			total += _get_slot_quantity(slot)
	return total


## Swap contents of two slots
func swap_slots(from_index: int, to_index: int) -> void:
	if from_index < 0 or from_index >= INVENTORY_SIZE:
		return
	if to_index < 0 or to_index >= INVENTORY_SIZE:
		return
	if from_index == to_index:
		return

	var temp: Dictionary = _slots[from_index]
	_slots[from_index] = _slots[to_index]
	_slots[to_index] = temp

	slot_updated.emit(from_index)
	slot_updated.emit(to_index)
	inventory_changed.emit()
	_queue_save()


## Merge from_slot into to_slot. Returns overflow remaining in from_slot
func merge_stacks(from_index: int, to_index: int) -> int:
	if from_index < 0 or from_index >= INVENTORY_SIZE:
		return 0
	if to_index < 0 or to_index >= INVENTORY_SIZE:
		return 0
	if from_index == to_index:
		return 0

	var from_slot: Dictionary = _slots[from_index]
	var to_slot: Dictionary = _slots[to_index]

	if from_slot.is_empty():
		return 0

	if to_slot.is_empty():
		# Just move to empty slot
		_slots[to_index] = from_slot
		_slots[from_index] = {}
		slot_updated.emit(from_index)
		slot_updated.emit(to_index)
		inventory_changed.emit()
		_queue_save()
		return 0

	# Can only merge same item types
	var from_item_id: StringName = get_slot_item_id(from_slot)
	var to_item_id: StringName = get_slot_item_id(to_slot)
	if from_item_id != to_item_id:
		return _get_slot_quantity(from_slot)
	var item_data: ItemData = get_item_data(from_item_id)
	if item_data == null:
		return _get_slot_quantity(from_slot)

	var total: int = _get_slot_quantity(from_slot) + _get_slot_quantity(to_slot)
	var max_stack: int = item_data.max_stack

	if total <= max_stack:
		_slots[to_index].quantity = total
		_slots[from_index] = {}
		slot_updated.emit(from_index)
		slot_updated.emit(to_index)
		inventory_changed.emit()
		_queue_save()
		return 0
	else:
		_slots[to_index].quantity = max_stack
		var overflow: int = total - max_stack
		_slots[from_index].quantity = overflow
		slot_updated.emit(from_index)
		slot_updated.emit(to_index)
		inventory_changed.emit()
		_queue_save()
		return overflow


## Split quantity from slot, returns data for held item or empty dict on failure
func split_from_slot(slot_index: int, quantity: int) -> Dictionary:
	if slot_index < 0 or slot_index >= INVENTORY_SIZE:
		return {}

	var slot: Dictionary = _slots[slot_index]
	if slot.is_empty():
		return {}

	var slot_quantity: int = _get_slot_quantity(slot)
	if quantity <= 0 or quantity >= slot_quantity:
		return {}

	var item_id: StringName = get_slot_item_id(slot)
	_slots[slot_index].quantity -= quantity

	slot_updated.emit(slot_index)
	inventory_changed.emit()
	_queue_save()

	return {"item_id": item_id, "quantity": quantity}


## Check if inventory has been loaded
func is_loaded() -> bool:
	return _is_loaded
