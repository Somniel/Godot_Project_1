class_name SteamInventoryStorage
extends InventoryStorage
## Stores inventory using Steam Inventory Service (server-authoritative).
## Items exist on Steam's servers and cannot be locally edited.
##
## To use this storage backend:
## 1. Configure item definitions in Steamworks partner portal
## 2. Replace SteamCloudStorage with SteamInventoryStorage in InventoryManager._setup_storage()
## 3. Update item spawning to use Steam grants instead of direct adds

## Maps our StringName IDs to Steam's numeric item definition IDs.
## Configure these in Steamworks partner portal first.
const ITEM_DEF_IDS: Dictionary = {
	&"air_pearl": 1001,    # Update with actual Steam item def IDs
	&"flame_pearl": 1002,
}

## Reverse mapping for looking up our IDs from Steam's IDs
var _steam_id_to_item_id: Dictionary = {}

var _slots: Array[Dictionary] = []
var _pending_result_handle: int = -1
var _is_loading: bool = false


func _init() -> void:
	_initialize_empty()
	# Build reverse mapping
	for item_id: StringName in ITEM_DEF_IDS:
		var steam_id: int = ITEM_DEF_IDS[item_id]
		_steam_id_to_item_id[steam_id] = item_id


func setup(_parent: Node) -> void:
	# Connect to Steam Inventory callbacks
	var steam: Object = SteamManager.get_steam()
	if steam == null:
		return

	# Note: Signal names may vary depending on GodotSteam version
	# @warning_ignore("unsafe_method_access")
	# steam.inventory_result_ready.connect(_on_inventory_result_ready)


func _initialize_empty() -> void:
	_slots.clear()
	for i: int in range(INVENTORY_SIZE):
		_slots.append({})


func load_inventory() -> void:
	if _is_loading:
		return

	var steam: Object = SteamManager.get_steam()
	if steam == null:
		_initialize_empty()
		load_completed.emit(false)
		return

	_is_loading = true

	# Request full inventory from Steam
	# @warning_ignore("unsafe_method_access")
	# _pending_result_handle = steam.getAllItems()

	# TODO: Implement actual Steam Inventory API calls
	# For now, emit failure to fall back gracefully
	push_warning("SteamInventoryStorage: Not yet implemented, using empty inventory")
	_initialize_empty()
	_is_loading = false
	load_completed.emit(false)


func save_inventory(_slots_to_save: Array[Dictionary]) -> void:
	# Steam Inventory is server-authoritative - changes happen through
	# consume/grant operations, not manual saves
	#
	# When transitioning to Steam Inventory:
	# - Item pickup calls steam.addPromoItem() or similar
	# - Item drop/use calls steam.consumeItem()
	# - Inventory state is always fetched from Steam, never written locally
	save_completed.emit(true)


func get_slots() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for slot: Dictionary in _slots:
		result.append(slot.duplicate())
	return result


func flush() -> void:
	# No local state to flush - Steam manages persistence
	pass


# =============================================================================
# Steam Inventory Callbacks (implement when ready)
# =============================================================================

func _on_inventory_result_ready(_result_handle: int, _result: int) -> void:
	# Called when Steam returns inventory data
	#
	# Implementation outline:
	# 1. Call steam.getResultItems(result_handle) to get item list
	# 2. Map Steam item instances to our slot format
	# 3. Store in _slots
	# 4. Emit load_completed(true)
	#
	# Note: Steam Inventory doesn't have "slots" - items are a flat list.
	# You'll need to decide how to map them to your 25-slot grid.
	pass


# =============================================================================
# Item Operations (call these instead of direct slot manipulation)
# =============================================================================

func grant_item(_item_id: StringName, _quantity: int) -> void:
	## Request Steam to grant an item to the player.
	## Used for drops, quest rewards, etc.
	#
	# var steam_def_id: int = ITEM_DEF_IDS.get(item_id, -1)
	# if steam_def_id == -1:
	#     push_warning("Unknown item: %s" % item_id)
	#     return
	# @warning_ignore("unsafe_method_access")
	# steam.addPromoItem(steam_def_id)
	pass


func consume_item(_item_id: StringName, _quantity: int) -> void:
	## Request Steam to consume (remove) an item from the player.
	## Used for crafting, dropping, using consumables, etc.
	#
	# Need to find the item instance ID first, then call:
	# @warning_ignore("unsafe_method_access")
	# steam.consumeItem(item_instance_id, quantity)
	pass
