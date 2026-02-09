extends GutTest
## Unit tests for NetworkManager autoload.
## Note: These tests run without an active network connection.


func test_initial_state() -> void:
	# NetworkManager should start inactive
	assert_false(NetworkManager.is_active(), "Should not be active initially")


func test_is_server_when_not_active() -> void:
	# Godot 4.5: without a peer, get_unique_id() returns 0 (not 1),
	# so is_server() returns false. The proper check is is_active() first.
	assert_false(NetworkManager.is_active(), "Should not be active")
	assert_false(NetworkManager.is_server(), "is_server returns false without a peer in 4.5")
	# Godot 4.5 emits an engine error when no peer is assigned — expected here
	for err: Variant in get_errors():
		err.handled = true


func test_get_unique_id_when_not_active() -> void:
	# Godot 4.5: get_unique_id() returns 0 when no peer is set (changed from 1).
	assert_false(NetworkManager.is_active(), "Should not be active")
	var result: int = NetworkManager.get_unique_id()
	assert_eq(result, 0, "get_unique_id returns 0 (no peer) in Godot 4.5")
	# Godot 4.5 emits an engine error when no peer is assigned — expected here
	for err: Variant in get_errors():
		err.handled = true


func test_disconnect_peer_when_not_connected() -> void:
	# Should not crash when disconnecting while not connected
	NetworkManager.disconnect_peer()
	assert_false(NetworkManager.is_active(), "Should still be inactive")
