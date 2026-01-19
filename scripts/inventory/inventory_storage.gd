class_name InventoryStorage
extends RefCounted
## Abstract base class for inventory persistence backends.
## Implementations handle loading/saving inventory data from different sources.

## Emitted when inventory load operation completes
signal load_completed(success: bool)

## Emitted when inventory save operation completes
signal save_completed(success: bool)

## Size of the inventory (number of slots)
const INVENTORY_SIZE: int = 25


## Called once after creation to set up timers or other node-dependent resources.
## @param parent: Node to attach child nodes to (e.g., timers)
func setup(_parent: Node) -> void:
	pass


## Begin loading inventory from storage. Emits load_completed when done.
func load_inventory() -> void:
	push_error("InventoryStorage.load_inventory() not implemented")
	load_completed.emit(false)


## Save inventory slots to storage. Emits save_completed when done.
## @param slots: Array of slot dictionaries with {item_id: StringName, quantity: int}
func save_inventory(_slots: Array[Dictionary]) -> void:
	push_error("InventoryStorage.save_inventory() not implemented")
	save_completed.emit(false)


## Get the current slot data after loading.
## @return: Array of slot dictionaries
func get_slots() -> Array[Dictionary]:
	push_error("InventoryStorage.get_slots() not implemented")
	return []


## Force immediate save if there's a pending debounced save.
## Called during cleanup (e.g., _exit_tree).
func flush() -> void:
	pass
