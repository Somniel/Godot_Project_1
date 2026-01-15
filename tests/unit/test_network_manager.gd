extends GutTest
## Unit tests for NetworkManager autoload.
## Note: These tests run without an active network connection.


func test_initial_state() -> void:
	# NetworkManager should start inactive
	assert_false(NetworkManager.is_active(), "Should not be active initially")


func test_is_server_when_not_active() -> void:
	# Note: Godot's multiplayer.is_server() returns true by default when no peer is set
	# This is expected behavior - you're the authority when offline
	# The proper check is to use is_active() first
	assert_false(NetworkManager.is_active(), "Should not be active")
	# is_server() will be true even when inactive (Godot default behavior)
	assert_true(NetworkManager.is_server(), "is_server returns true by default in Godot")


func test_get_unique_id_when_not_active() -> void:
	# Note: Godot's multiplayer.get_unique_id() returns 1 (server ID) by default
	# when no peer is set. This is expected Godot behavior.
	assert_false(NetworkManager.is_active(), "Should not be active")
	var result: int = NetworkManager.get_unique_id()
	assert_eq(result, 1, "get_unique_id returns 1 (server) by default in Godot")


func test_disconnect_peer_when_not_connected() -> void:
	# Should not crash when disconnecting while not connected
	NetworkManager.disconnect_peer()
	assert_false(NetworkManager.is_active(), "Should still be inactive")
