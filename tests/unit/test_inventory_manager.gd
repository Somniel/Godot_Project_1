extends GutTest
## Unit tests for InventoryManager autoload.
## Tests core slot manipulation logic independent of Steam persistence.


# =============================================================================
# Test Fixtures
# =============================================================================

## Mock ItemData for testing
var _test_item_a: ItemData = null
var _test_item_b: ItemData = null


func before_each() -> void:
	# Clear all slots before each test
	for i: int in range(InventoryManager.INVENTORY_SIZE):
		# Directly clear without triggering saves
		InventoryManager._slots[i] = {}

	# Create test items if not already created
	if _test_item_a == null:
		_test_item_a = ItemData.new()
		_test_item_a.id = &"test_item_a"
		_test_item_a.display_name = "Test Item A"
		_test_item_a.max_stack = 10

	if _test_item_b == null:
		_test_item_b = ItemData.new()
		_test_item_b.id = &"test_item_b"
		_test_item_b.display_name = "Test Item B"
		_test_item_b.max_stack = 5

	# Register test items
	InventoryManager.register_item(_test_item_a)
	InventoryManager.register_item(_test_item_b)


# =============================================================================
# Item Registry Tests
# =============================================================================

func test_register_item_stores_data() -> void:
	var item: ItemData = InventoryManager.get_item_data(&"test_item_a")
	assert_not_null(item, "Registered item should be retrievable")
	assert_eq(item.id, &"test_item_a", "Item ID should match")


func test_get_item_data_returns_null_for_unknown() -> void:
	var item: ItemData = InventoryManager.get_item_data(&"nonexistent_item")
	assert_null(item, "Unknown item should return null")


func test_register_item_rejects_null() -> void:
	# This test verifies null items are rejected (warning is expected behavior)
	var registry_size_before: int = InventoryManager._item_registry.size()

	InventoryManager.register_item(null)

	# Mark the expected warning as handled so GUT doesn't fail the test
	var errors: Array = get_errors()
	for err in errors:
		if err.contains_text("Cannot register null"):
			err.handled = true

	# Verify null wasn't added to registry
	var registry_size_after: int = InventoryManager._item_registry.size()
	assert_eq(registry_size_before, registry_size_after, "Null item should not be registered")


func test_register_item_rejects_empty_id() -> void:
	# This test verifies empty ID items are rejected (warning is expected behavior)
	var empty_item: ItemData = ItemData.new()
	empty_item.id = &""

	var registry_size_before: int = InventoryManager._item_registry.size()

	InventoryManager.register_item(empty_item)

	# Mark the expected warning as handled so GUT doesn't fail the test
	var errors: Array = get_errors()
	for err in errors:
		if err.contains_text("Cannot register null"):
			err.handled = true

	# Should not be registered
	var registry_size_after: int = InventoryManager._item_registry.size()
	assert_eq(registry_size_before, registry_size_after, "Empty ID item should not be registered")


# =============================================================================
# Add Item Tests
# =============================================================================

func test_add_item_to_empty_inventory() -> void:
	var overflow: int = InventoryManager.add_item(&"test_item_a", 5)

	assert_eq(overflow, 0, "Should have no overflow")
	assert_eq(InventoryManager.get_item_count(&"test_item_a"), 5, "Should have 5 items")

	var slot: Dictionary = InventoryManager.get_slot(0)
	assert_eq(slot.get("item_id"), &"test_item_a", "First slot should have item")
	assert_eq(slot.get("quantity"), 5, "First slot should have quantity 5")


func test_add_item_stacks_with_existing() -> void:
	InventoryManager.add_item(&"test_item_a", 3)
	InventoryManager.add_item(&"test_item_a", 4)

	assert_eq(InventoryManager.get_item_count(&"test_item_a"), 7, "Should have 7 total")

	var slot: Dictionary = InventoryManager.get_slot(0)
	assert_eq(slot.get("quantity"), 7, "Should be stacked in one slot")

	# Second slot should be empty
	assert_true(InventoryManager.is_slot_empty(1), "Second slot should be empty")


func test_add_item_respects_max_stack() -> void:
	# max_stack for test_item_a is 10
	InventoryManager.add_item(&"test_item_a", 15)

	assert_eq(InventoryManager.get_item_count(&"test_item_a"), 15, "Should have 15 total")

	var slot0: Dictionary = InventoryManager.get_slot(0)
	var slot1: Dictionary = InventoryManager.get_slot(1)

	assert_eq(slot0.get("quantity"), 10, "First slot should be at max stack")
	assert_eq(slot1.get("quantity"), 5, "Overflow should go to second slot")


func test_add_item_returns_overflow_when_full() -> void:
	# Fill all 25 slots with max stacks (10 each = 250 items)
	for i: int in range(InventoryManager.INVENTORY_SIZE):
		InventoryManager._slots[i] = {"item_id": &"test_item_a", "quantity": 10}

	var overflow: int = InventoryManager.add_item(&"test_item_a", 5)

	assert_eq(overflow, 5, "Should return all items as overflow when full")


func test_add_item_partial_overflow() -> void:
	# Fill all but one slot, leave one slot with partial stack
	for i: int in range(InventoryManager.INVENTORY_SIZE - 1):
		InventoryManager._slots[i] = {"item_id": &"test_item_a", "quantity": 10}
	InventoryManager._slots[InventoryManager.INVENTORY_SIZE - 1] = {
		"item_id": &"test_item_a", "quantity": 7
	}

	# Try to add 5 more (only 3 space available)
	var overflow: int = InventoryManager.add_item(&"test_item_a", 5)

	assert_eq(overflow, 2, "Should return 2 as overflow")
	assert_eq(
		InventoryManager._slots[InventoryManager.INVENTORY_SIZE - 1].get("quantity"),
		10,
		"Last slot should be full"
	)


func test_add_unknown_item_returns_full_quantity() -> void:
	# This test verifies unknown items are rejected (warning is expected behavior)
	var overflow: int = InventoryManager.add_item(&"unknown_item", 5)

	# Mark the expected warning as handled so GUT doesn't fail the test
	var errors: Array = get_errors()
	for err in errors:
		if err.contains_text("Unknown item"):
			err.handled = true

	assert_eq(overflow, 5, "Should return all items for unknown item type")
	assert_eq(InventoryManager.get_item_count(&"unknown_item"), 0, "Unknown item should not be added")


func test_add_item_zero_quantity() -> void:
	var overflow: int = InventoryManager.add_item(&"test_item_a", 0)
	assert_eq(overflow, 0, "Zero quantity should return 0 overflow")
	assert_eq(InventoryManager.get_item_count(&"test_item_a"), 0, "Should not add anything")


func test_add_item_negative_quantity() -> void:
	var overflow: int = InventoryManager.add_item(&"test_item_a", -5)
	assert_eq(overflow, 0, "Negative quantity should return 0 overflow")


func test_add_item_emits_signals() -> void:
	watch_signals(InventoryManager)

	InventoryManager.add_item(&"test_item_a", 5)

	assert_signal_emitted(InventoryManager, "item_added", "Should emit item_added")
	assert_signal_emitted(InventoryManager, "inventory_changed", "Should emit inventory_changed")
	assert_signal_emitted(InventoryManager, "slot_updated", "Should emit slot_updated")


func test_add_item_emits_inventory_full_when_overflow() -> void:
	# Fill inventory
	for i: int in range(InventoryManager.INVENTORY_SIZE):
		InventoryManager._slots[i] = {"item_id": &"test_item_a", "quantity": 10}

	watch_signals(InventoryManager)

	InventoryManager.add_item(&"test_item_a", 5)

	assert_signal_emitted(InventoryManager, "inventory_full", "Should emit inventory_full")


# =============================================================================
# Remove From Slot Tests
# =============================================================================

func test_remove_from_slot_decreases_quantity() -> void:
	InventoryManager.add_item(&"test_item_a", 10)

	var success: bool = InventoryManager.remove_from_slot(0, 3)

	assert_true(success, "Should succeed")
	assert_eq(InventoryManager.get_slot(0).get("quantity"), 7, "Should have 7 remaining")


func test_remove_from_slot_clears_when_zero() -> void:
	InventoryManager.add_item(&"test_item_a", 5)

	var success: bool = InventoryManager.remove_from_slot(0, 5)

	assert_true(success, "Should succeed")
	assert_true(InventoryManager.is_slot_empty(0), "Slot should be empty")


func test_remove_from_slot_fails_if_insufficient() -> void:
	InventoryManager.add_item(&"test_item_a", 3)

	var success: bool = InventoryManager.remove_from_slot(0, 5)

	assert_false(success, "Should fail when insufficient quantity")
	assert_eq(InventoryManager.get_slot(0).get("quantity"), 3, "Quantity should be unchanged")


func test_remove_from_slot_fails_on_empty_slot() -> void:
	var success: bool = InventoryManager.remove_from_slot(0, 1)
	assert_false(success, "Should fail on empty slot")


func test_remove_from_slot_invalid_index() -> void:
	var success_negative: bool = InventoryManager.remove_from_slot(-1, 1)
	var success_too_high: bool = InventoryManager.remove_from_slot(100, 1)

	assert_false(success_negative, "Should fail with negative index")
	assert_false(success_too_high, "Should fail with index too high")


func test_remove_from_slot_emits_signals() -> void:
	InventoryManager.add_item(&"test_item_a", 5)
	watch_signals(InventoryManager)

	InventoryManager.remove_from_slot(0, 2)

	assert_signal_emitted(InventoryManager, "item_removed", "Should emit item_removed")
	assert_signal_emitted(InventoryManager, "inventory_changed", "Should emit inventory_changed")
	assert_signal_emitted(InventoryManager, "slot_updated", "Should emit slot_updated")


# =============================================================================
# Set/Clear Slot Tests
# =============================================================================

func test_set_slot_creates_item() -> void:
	InventoryManager.set_slot(5, &"test_item_a", 7)

	var slot: Dictionary = InventoryManager.get_slot(5)
	assert_eq(slot.get("item_id"), &"test_item_a", "Should have correct item")
	assert_eq(slot.get("quantity"), 7, "Should have correct quantity")


func test_set_slot_overwrites_existing() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)
	InventoryManager.set_slot(0, &"test_item_b", 3)

	var slot: Dictionary = InventoryManager.get_slot(0)
	assert_eq(slot.get("item_id"), &"test_item_b", "Should have new item")
	assert_eq(slot.get("quantity"), 3, "Should have new quantity")


func test_set_slot_clears_with_zero_quantity() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)
	InventoryManager.set_slot(0, &"test_item_a", 0)

	assert_true(InventoryManager.is_slot_empty(0), "Should be empty with zero quantity")


func test_set_slot_clears_with_empty_id() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)
	InventoryManager.set_slot(0, &"", 5)

	assert_true(InventoryManager.is_slot_empty(0), "Should be empty with empty item ID")


func test_set_slot_invalid_index() -> void:
	# Should not crash
	InventoryManager.set_slot(-1, &"test_item_a", 5)
	InventoryManager.set_slot(100, &"test_item_a", 5)
	assert_true(true, "Should handle invalid indices gracefully")


func test_clear_slot_empties_slot() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)
	InventoryManager.clear_slot(0)

	assert_true(InventoryManager.is_slot_empty(0), "Slot should be empty after clear")


func test_clear_slot_invalid_index() -> void:
	# Should not crash
	InventoryManager.clear_slot(-1)
	InventoryManager.clear_slot(100)
	assert_true(true, "Should handle invalid indices gracefully")


# =============================================================================
# Swap Slots Tests
# =============================================================================

func test_swap_slots_exchanges_contents() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)
	InventoryManager.set_slot(1, &"test_item_b", 3)

	InventoryManager.swap_slots(0, 1)

	var slot0: Dictionary = InventoryManager.get_slot(0)
	var slot1: Dictionary = InventoryManager.get_slot(1)

	assert_eq(slot0.get("item_id"), &"test_item_b", "Slot 0 should have item B")
	assert_eq(slot0.get("quantity"), 3, "Slot 0 should have quantity 3")
	assert_eq(slot1.get("item_id"), &"test_item_a", "Slot 1 should have item A")
	assert_eq(slot1.get("quantity"), 5, "Slot 1 should have quantity 5")


func test_swap_slots_works_with_empty() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)

	InventoryManager.swap_slots(0, 1)

	assert_true(InventoryManager.is_slot_empty(0), "Slot 0 should be empty")
	assert_eq(InventoryManager.get_slot(1).get("item_id"), &"test_item_a", "Slot 1 should have item")


func test_swap_slots_same_index_no_change() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)

	InventoryManager.swap_slots(0, 0)

	assert_eq(InventoryManager.get_slot(0).get("quantity"), 5, "Should be unchanged")


func test_swap_slots_invalid_indices() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)

	# Should not crash or change anything
	InventoryManager.swap_slots(-1, 0)
	InventoryManager.swap_slots(0, 100)

	assert_eq(InventoryManager.get_slot(0).get("quantity"), 5, "Should be unchanged")


func test_swap_slots_emits_signals() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)
	InventoryManager.set_slot(1, &"test_item_b", 3)
	watch_signals(InventoryManager)

	InventoryManager.swap_slots(0, 1)

	assert_signal_emitted(InventoryManager, "inventory_changed", "Should emit inventory_changed")
	# slot_updated should be emitted twice (for both slots)
	assert_signal_emit_count(InventoryManager, "slot_updated", 2, "Should emit slot_updated twice")


# =============================================================================
# Merge Stacks Tests
# =============================================================================

func test_merge_stacks_combines_same_items() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 3)
	InventoryManager.set_slot(1, &"test_item_a", 4)

	var overflow: int = InventoryManager.merge_stacks(0, 1)

	assert_eq(overflow, 0, "Should have no overflow")
	assert_true(InventoryManager.is_slot_empty(0), "Source slot should be empty")
	assert_eq(InventoryManager.get_slot(1).get("quantity"), 7, "Target should have combined total")


func test_merge_stacks_returns_overflow() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 7)
	InventoryManager.set_slot(1, &"test_item_a", 6)

	# max_stack is 10, so 7 + 6 = 13, overflow = 3
	var overflow: int = InventoryManager.merge_stacks(0, 1)

	assert_eq(overflow, 3, "Should return overflow of 3")
	assert_eq(InventoryManager.get_slot(0).get("quantity"), 3, "Source should have overflow")
	assert_eq(InventoryManager.get_slot(1).get("quantity"), 10, "Target should be at max stack")


func test_merge_stacks_rejects_different_items() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)
	InventoryManager.set_slot(1, &"test_item_b", 3)

	var overflow: int = InventoryManager.merge_stacks(0, 1)

	assert_eq(overflow, 5, "Should return source quantity as overflow")
	assert_eq(InventoryManager.get_slot(0).get("quantity"), 5, "Source should be unchanged")
	assert_eq(InventoryManager.get_slot(1).get("quantity"), 3, "Target should be unchanged")


func test_merge_stacks_moves_to_empty_slot() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)

	var overflow: int = InventoryManager.merge_stacks(0, 1)

	assert_eq(overflow, 0, "Should have no overflow")
	assert_true(InventoryManager.is_slot_empty(0), "Source should be empty")
	assert_eq(InventoryManager.get_slot(1).get("quantity"), 5, "Target should have items")


func test_merge_stacks_from_empty_slot() -> void:
	InventoryManager.set_slot(1, &"test_item_a", 5)

	var overflow: int = InventoryManager.merge_stacks(0, 1)

	assert_eq(overflow, 0, "Should return 0 for empty source")
	assert_eq(InventoryManager.get_slot(1).get("quantity"), 5, "Target should be unchanged")


func test_merge_stacks_same_slot() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)

	var overflow: int = InventoryManager.merge_stacks(0, 0)

	assert_eq(overflow, 0, "Should return 0 for same slot")
	assert_eq(InventoryManager.get_slot(0).get("quantity"), 5, "Should be unchanged")


# =============================================================================
# Split From Slot Tests
# =============================================================================

func test_split_from_slot_divides_stack() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 10)

	var split_data: Dictionary = InventoryManager.split_from_slot(0, 4)

	assert_eq(split_data.get("item_id"), &"test_item_a", "Split data should have item ID")
	assert_eq(split_data.get("quantity"), 4, "Split data should have split quantity")
	assert_eq(InventoryManager.get_slot(0).get("quantity"), 6, "Slot should have remainder")


func test_split_from_slot_fails_if_quantity_too_high() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)

	var split_data: Dictionary = InventoryManager.split_from_slot(0, 5)

	assert_true(split_data.is_empty(), "Should return empty dict when splitting all")


func test_split_from_slot_fails_if_quantity_exceeds() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)

	var split_data: Dictionary = InventoryManager.split_from_slot(0, 10)

	assert_true(split_data.is_empty(), "Should return empty dict when quantity exceeds")


func test_split_from_slot_fails_zero_quantity() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)

	var split_data: Dictionary = InventoryManager.split_from_slot(0, 0)

	assert_true(split_data.is_empty(), "Should return empty dict for zero quantity")


func test_split_from_slot_fails_negative_quantity() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)

	var split_data: Dictionary = InventoryManager.split_from_slot(0, -1)

	assert_true(split_data.is_empty(), "Should return empty dict for negative quantity")


func test_split_from_slot_fails_empty_slot() -> void:
	var split_data: Dictionary = InventoryManager.split_from_slot(0, 3)

	assert_true(split_data.is_empty(), "Should return empty dict for empty slot")


func test_split_from_slot_invalid_index() -> void:
	var split_negative: Dictionary = InventoryManager.split_from_slot(-1, 3)
	var split_high: Dictionary = InventoryManager.split_from_slot(100, 3)

	assert_true(split_negative.is_empty(), "Should return empty for negative index")
	assert_true(split_high.is_empty(), "Should return empty for high index")


# =============================================================================
# Query Method Tests
# =============================================================================

func test_has_item_checks_total_across_slots() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)
	InventoryManager.set_slot(5, &"test_item_a", 3)

	assert_true(InventoryManager.has_item(&"test_item_a", 8), "Should have 8 total")
	assert_true(InventoryManager.has_item(&"test_item_a", 5), "Should have at least 5")
	assert_false(InventoryManager.has_item(&"test_item_a", 9), "Should not have 9")


func test_has_item_returns_false_for_zero() -> void:
	assert_false(InventoryManager.has_item(&"test_item_a", 1), "Should not have item not added")


func test_get_item_count_sums_all_slots() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)
	InventoryManager.set_slot(3, &"test_item_a", 7)
	InventoryManager.set_slot(10, &"test_item_a", 2)
	InventoryManager.set_slot(1, &"test_item_b", 4)  # Different item

	assert_eq(InventoryManager.get_item_count(&"test_item_a"), 14, "Should sum all slots")
	assert_eq(InventoryManager.get_item_count(&"test_item_b"), 4, "Should count separately")


func test_get_item_count_returns_zero_for_missing() -> void:
	assert_eq(InventoryManager.get_item_count(&"nonexistent"), 0, "Should return 0")


func test_find_empty_slot_returns_first_empty() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)
	InventoryManager.set_slot(1, &"test_item_a", 5)

	var empty_idx: int = InventoryManager.find_empty_slot()

	assert_eq(empty_idx, 2, "Should return first empty slot (index 2)")


func test_find_empty_slot_returns_negative_when_full() -> void:
	for i: int in range(InventoryManager.INVENTORY_SIZE):
		InventoryManager._slots[i] = {"item_id": &"test_item_a", "quantity": 1}

	var empty_idx: int = InventoryManager.find_empty_slot()

	assert_eq(empty_idx, -1, "Should return -1 when full")


func test_find_slot_with_space_finds_partial_stack() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 10)  # Full stack
	InventoryManager.set_slot(1, &"test_item_b", 2)   # Different item
	InventoryManager.set_slot(2, &"test_item_a", 5)   # Partial stack

	var slot_idx: int = InventoryManager.find_slot_with_space(&"test_item_a")

	assert_eq(slot_idx, 2, "Should find slot 2 with partial stack")


func test_find_slot_with_space_returns_negative_when_all_full() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 10)  # Full stack

	var slot_idx: int = InventoryManager.find_slot_with_space(&"test_item_a")

	assert_eq(slot_idx, -1, "Should return -1 when all stacks are full")


func test_find_slot_with_space_returns_negative_for_unknown_item() -> void:
	var slot_idx: int = InventoryManager.find_slot_with_space(&"unknown")

	assert_eq(slot_idx, -1, "Should return -1 for unknown item")


func test_is_slot_empty_true_for_empty() -> void:
	assert_true(InventoryManager.is_slot_empty(0), "Fresh slot should be empty")


func test_is_slot_empty_false_for_filled() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 1)
	assert_false(InventoryManager.is_slot_empty(0), "Filled slot should not be empty")


func test_is_slot_empty_true_for_invalid_index() -> void:
	assert_true(InventoryManager.is_slot_empty(-1), "Invalid index should be considered empty")
	assert_true(InventoryManager.is_slot_empty(100), "Invalid index should be considered empty")


func test_get_slot_returns_copy() -> void:
	InventoryManager.set_slot(0, &"test_item_a", 5)

	var slot: Dictionary = InventoryManager.get_slot(0)
	slot["quantity"] = 999  # Modify the copy

	# Original should be unchanged
	assert_eq(InventoryManager.get_slot(0).get("quantity"), 5, "Should return copy, not reference")


func test_get_slot_invalid_index_returns_empty() -> void:
	var slot_negative: Dictionary = InventoryManager.get_slot(-1)
	var slot_high: Dictionary = InventoryManager.get_slot(100)

	assert_true(slot_negative.is_empty(), "Invalid index should return empty dict")
	assert_true(slot_high.is_empty(), "Invalid index should return empty dict")


# =============================================================================
# is_loaded Tests
# =============================================================================

func test_is_loaded_returns_bool() -> void:
	# Just verify it returns a bool without crashing
	var loaded: bool = InventoryManager.is_loaded()
	assert_true(loaded is bool, "Should return a boolean")
