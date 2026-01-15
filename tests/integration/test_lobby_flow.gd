extends GutTest
## Integration tests for the lobby creation and joining flow.
## These tests require Steam to be running and connected.


func before_all() -> void:
	# Check if Steam is available for integration tests
	if not SteamManager.is_steam_initialized:
		pending("Steam not initialized - skipping integration tests")


func test_create_and_leave_lobby() -> void:
	if not SteamManager.is_steam_initialized:
		pending("Steam not initialized")
		return

	watch_signals(LobbyManager)

	# Create a lobby
	LobbyManager.create_lobby(4)

	# Wait for lobby creation (up to 5 seconds)
	await wait_for_signal(LobbyManager.lobby_created, 5.0)

	if get_signal_emit_count(LobbyManager, "lobby_created") == 0:
		fail_test("Lobby creation timed out")
		return

	# Verify lobby was created
	assert_gt(LobbyManager.current_lobby_id, 0, "Should have valid lobby ID")
	assert_true(LobbyManager.is_host, "Should be host")

	# Leave the lobby
	LobbyManager.leave_lobby()

	# Verify we left
	assert_eq(LobbyManager.current_lobby_id, 0, "Should have no lobby after leaving")
	assert_false(LobbyManager.is_host, "Should not be host after leaving")


func test_lobby_metadata_roundtrip() -> void:
	if not SteamManager.is_steam_initialized:
		pending("Steam not initialized")
		return

	watch_signals(LobbyManager)

	# Create a lobby
	LobbyManager.create_lobby(4)
	await wait_for_signal(LobbyManager.lobby_created, 5.0)

	if LobbyManager.current_lobby_id == 0:
		fail_test("Could not create lobby for metadata test")
		return

	# Set custom metadata
	var success: bool = LobbyManager.set_lobby_metadata("test_key", "test_value")
	assert_true(success, "Should successfully set metadata")

	# Read it back
	var value: String = LobbyManager.get_lobby_metadata(
		LobbyManager.current_lobby_id, "test_key"
	)
	assert_eq(value, "test_value", "Should read back the same value")

	# Cleanup
	LobbyManager.leave_lobby()


func test_lobby_list_request() -> void:
	if not SteamManager.is_steam_initialized:
		pending("Steam not initialized")
		return

	watch_signals(LobbyManager)

	# Request lobby list
	LobbyManager.request_lobby_list()

	# Wait for response (up to 10 seconds for network)
	await wait_for_signal(LobbyManager.lobby_list_received, 10.0)

	assert_signal_emitted(LobbyManager, "lobby_list_received")
	# Note: We can't assert the content since it depends on active lobbies
