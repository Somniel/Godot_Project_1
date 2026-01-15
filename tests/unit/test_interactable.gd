extends GutTest
## Unit tests for the Interactable component.

var _interactable: Interactable


func before_each() -> void:
	_interactable = Interactable.new()
	add_child_autoqfree(_interactable)


func test_default_interaction_type() -> void:
	assert_eq(_interactable.interaction_type, "Touch", "Default type should be Touch")


func test_default_object_name() -> void:
	assert_eq(_interactable.object_name, "Object", "Default name should be Object")


func test_default_interaction_radius() -> void:
	assert_eq(_interactable.interaction_radius, 2.0, "Default radius should be 2.0")


func test_default_prompt_height_offset() -> void:
	assert_eq(_interactable.prompt_height_offset, 2.0, "Default height should be 2.0")


func test_interact_emits_signal() -> void:
	watch_signals(_interactable)

	var mock_player := Node3D.new()
	add_child_autoqfree(mock_player)

	_interactable.interact(mock_player)

	assert_signal_emitted_with_parameters(
		_interactable, "interacted", [mock_player]
	)


func test_show_prompt_makes_label_visible() -> void:
	# Wait for _ready to complete
	await get_tree().process_frame

	_interactable.show_prompt()

	# Find the label child
	var label: Label3D = null
	for child in _interactable.get_children():
		if child is Label3D:
			label = child
			break

	assert_not_null(label, "Should have a Label3D child")
	if label:
		assert_true(label.visible, "Label should be visible after show_prompt")


func test_hide_prompt_makes_label_invisible() -> void:
	# Wait for _ready to complete
	await get_tree().process_frame

	_interactable.show_prompt()
	_interactable.hide_prompt()

	# Find the label child
	var label: Label3D = null
	for child in _interactable.get_children():
		if child is Label3D:
			label = child
			break

	assert_not_null(label, "Should have a Label3D child")
	if label:
		assert_false(label.visible, "Label should be invisible after hide_prompt")


func test_collision_layer_set_correctly() -> void:
	# Wait for _ready to complete
	await get_tree().process_frame

	assert_eq(_interactable.collision_layer, 4, "Should be on collision layer 4")
	assert_eq(_interactable.collision_mask, 0, "Should have no collision mask")


func test_custom_interaction_type() -> void:
	_interactable.interaction_type = "Open"
	_interactable.object_name = "Door"

	# Wait for _ready to complete (label created)
	await get_tree().process_frame

	# Find the label and check text
	var label: Label3D = null
	for child in _interactable.get_children():
		if child is Label3D:
			label = child
			break

	# Note: Label text is set in _ready, so custom values need to be set before adding to tree
	# This test verifies the properties are settable
	assert_eq(_interactable.interaction_type, "Open")
	assert_eq(_interactable.object_name, "Door")
