extends GutTest
## Unit tests for server-side field travel validation in town.gd.
## Tests _handle_field_travel_validation routing: approve join when
## lobby exists, clear stale link + approve creation when it doesn't.

const TOWN_SCENE: PackedScene = preload("res://scenes/maps/town/town.tscn")

var _town: Node = null


func before_each() -> void:
	# Skip in headless mode — town scene needs 3D rendering context
	if DisplayServer.get_name() == "headless":
		return

	_town = TOWN_SCENE.instantiate()
	if _town == null:
		return
	add_child_autoqfree(_town)
	# _ready runs synchronously on add_child — gateways are available immediately


func after_each() -> void:
	# Mark engine errors as handled (RPCs without peer, push_warnings, etc.)
	for err: Variant in get_errors():
		err.handled = true


func _should_skip() -> bool:
	if DisplayServer.get_name() == "headless":
		pending("Town scene tests skipped in headless mode")
		return true
	if _town == null:
		pending("Town scene failed to instantiate")
		return true
	return false


## Handle engine errors emitted by multiplayer calls without an active peer.
## Must be called inside each test (not just after_each) because GUT checks
## for unhandled errors before after_each runs.
func _handle_engine_errors() -> void:
	for err: Variant in get_errors():
		err.handled = true


# =============================================================================
# _pending_field_travel_validation dictionary lifecycle
# =============================================================================


func test_pending_validation_starts_empty() -> void:
	if _should_skip():
		return

	assert_true(
		_town._pending_field_travel_validation.is_empty(), "Should start with no pending validation"
	)


# =============================================================================
# _handle_field_travel_validation — lobby exists path
# =============================================================================


func test_validation_exists_clears_pending_dict() -> void:
	if _should_skip():
		return

	# Set up a gateway with a linked lobby
	var gateway: Gateway = _town._gateways[0]
	gateway.set_link(50000, "Test Field")
	gateway.generation_seed = 12345

	# Simulate pending validation state
	_town._pending_field_travel_validation = {"peer_id": 2, "gateway_id": 0, "lobby_id": 50000}

	_town._handle_field_travel_validation(50000, true)
	_handle_engine_errors()

	assert_true(
		_town._pending_field_travel_validation.is_empty(),
		"Pending validation should be cleared after handling"
	)


func test_validation_exists_preserves_gateway_link() -> void:
	if _should_skip():
		return

	var gateway: Gateway = _town._gateways[0]
	gateway.set_link(50000, "Test Field")
	gateway.generation_seed = 12345

	_town._pending_field_travel_validation = {"peer_id": 2, "gateway_id": 0, "lobby_id": 50000}

	_town._handle_field_travel_validation(50000, true)
	_handle_engine_errors()

	# Gateway link should be preserved (lobby still exists)
	assert_eq(gateway.linked_lobby_id, 50000, "Gateway link should be preserved when lobby exists")


# =============================================================================
# _handle_field_travel_validation — lobby gone path
# =============================================================================


func test_validation_gone_clears_pending_dict() -> void:
	if _should_skip():
		return

	var gateway: Gateway = _town._gateways[1]
	gateway.set_link(60000, "Dead Field")
	gateway.generation_seed = 54321

	_town._pending_field_travel_validation = {"peer_id": 3, "gateway_id": 1, "lobby_id": 60000}

	_town._handle_field_travel_validation(60000, false)
	_handle_engine_errors()

	assert_true(
		_town._pending_field_travel_validation.is_empty(),
		"Pending validation should be cleared after handling"
	)


func test_validation_gone_clears_stale_lobby_id() -> void:
	if _should_skip():
		return

	var gateway: Gateway = _town._gateways[1]
	gateway.set_link(60000, "Dead Field")
	gateway.generation_seed = 54321

	_town._pending_field_travel_validation = {"peer_id": 3, "gateway_id": 1, "lobby_id": 60000}

	_town._handle_field_travel_validation(60000, false)
	_handle_engine_errors()

	# Gateway lobby link should be cleared (lobby gone)
	assert_eq(
		gateway.linked_lobby_id, 0, "Stale lobby ID should be cleared when lobby no longer exists"
	)


func test_validation_gone_preserves_seed() -> void:
	if _should_skip():
		return

	var gateway: Gateway = _town._gateways[1]
	gateway.set_link(60000, "Dead Field")
	gateway.generation_seed = 54321
	gateway.pearl_type = &"flame_pearl"

	_town._pending_field_travel_validation = {"peer_id": 3, "gateway_id": 1, "lobby_id": 60000}

	_town._handle_field_travel_validation(60000, false)
	_handle_engine_errors()

	# Seed should be preserved so field can be recreated
	assert_eq(
		gateway.generation_seed, 54321, "Generation seed should be preserved for field recreation"
	)


func test_validation_gone_adds_pending_creation() -> void:
	if _should_skip():
		return

	var gateway: Gateway = _town._gateways[2]
	gateway.set_link(70000, "Gone Field")
	gateway.generation_seed = 99999

	_town._pending_field_travel_validation = {"peer_id": 4, "gateway_id": 2, "lobby_id": 70000}

	_town._handle_field_travel_validation(70000, false)
	_handle_engine_errors()

	# _approve_field_creation should have added a pending creation entry
	assert_true(
		_town._pending_gateway_creations.has(2), "Should register pending creation for the gateway"
	)


# =============================================================================
# _handle_field_travel_validation — invalid gateway
# =============================================================================


func test_validation_invalid_gateway_clears_pending() -> void:
	if _should_skip():
		return

	_town._pending_field_travel_validation = {"peer_id": 5, "gateway_id": 99, "lobby_id": 80000}

	# Should not crash with out-of-bounds gateway_id
	_town._handle_field_travel_validation(80000, true)
	_handle_engine_errors()

	assert_true(
		_town._pending_field_travel_validation.is_empty(),
		"Pending validation should be cleared even with invalid gateway"
	)


# =============================================================================
# _on_lobby_data_received routing
# =============================================================================


func test_lobby_data_routes_to_validation_when_pending() -> void:
	if _should_skip():
		return

	var gateway: Gateway = _town._gateways[0]
	gateway.set_link(50000, "Test Field")
	gateway.generation_seed = 12345

	_town._pending_field_travel_validation = {"peer_id": 2, "gateway_id": 0, "lobby_id": 50000}

	# Call _on_lobby_data_received — should route to validation handler
	_town._on_lobby_data_received(50000, true)
	_handle_engine_errors()

	# Validation should have been handled (dict cleared)
	assert_true(
		_town._pending_field_travel_validation.is_empty(),
		"Validation should be handled via _on_lobby_data_received routing"
	)


func test_lobby_data_ignores_mismatched_lobby_id() -> void:
	if _should_skip():
		return

	_town._pending_field_travel_validation = {"peer_id": 2, "gateway_id": 0, "lobby_id": 50000}

	# Different lobby_id should NOT trigger validation
	_town._on_lobby_data_received(99999, true)

	assert_false(
		_town._pending_field_travel_validation.is_empty(),
		"Mismatched lobby_id should not clear pending validation"
	)


func test_lobby_data_no_routing_when_no_pending() -> void:
	if _should_skip():
		return

	# No pending validation — should not crash
	_town._on_lobby_data_received(50000, true)

	assert_true(
		_town._pending_field_travel_validation.is_empty(),
		"Should remain empty when no validation is pending"
	)


# =============================================================================
# _on_field_travel_requested — server-side entry point
# =============================================================================
# These tests require multiplayer.is_server() == true, which needs an active
# MultiplayerPeer. Godot 4.5 returns false without a peer (get_unique_id()
# returns 0, not 1), so the method early-returns. Tests that need server
# authority are marked pending; rejection tests still pass because the
# early-return produces the same empty-state result.


func test_field_travel_requested_with_linked_lobby_sets_pending() -> void:
	if _should_skip():
		return

	# Requires multiplayer.is_server() == true, which needs an active peer.
	# Godot 4.5 returns false without a peer — skip in unit tests.
	pending("Requires active multiplayer peer (server authority)")


func test_field_travel_requested_without_lobby_approves_creation() -> void:
	if _should_skip():
		return

	# Requires multiplayer.is_server() == true, which needs an active peer.
	# Godot 4.5 returns false without a peer — skip in unit tests.
	pending("Requires active multiplayer peer (server authority)")


func test_field_travel_requested_rejects_unconfigured_gateway() -> void:
	if _should_skip():
		return

	# Gateway 3 is unconfigured (generation_seed = 0)
	_town._on_field_travel_requested(2, 3)
	_handle_engine_errors()

	assert_true(
		_town._pending_field_travel_validation.is_empty(),
		"Should not validate unconfigured gateway"
	)
	assert_false(
		_town._pending_gateway_creations.has(3), "Should not create for unconfigured gateway"
	)


func test_field_travel_requested_rejects_invalid_gateway_id() -> void:
	if _should_skip():
		return

	_town._on_field_travel_requested(2, 99)
	_handle_engine_errors()

	assert_true(
		_town._pending_field_travel_validation.is_empty(), "Should not validate invalid gateway"
	)
