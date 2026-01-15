extends GutTest
## Unit tests for LobbyManager autoload.
## Note: These tests run without Steam connected, testing offline behavior.


func test_initial_state() -> void:
	assert_eq(LobbyManager.current_lobby_id, 0, "Should start with no lobby")
	assert_false(LobbyManager.is_host, "Should not be host initially")


func test_create_lobby_without_steam_emits_failure() -> void:
	# Skip if Steam is actually initialized
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	# Watch for the failure signal
	watch_signals(LobbyManager)

	LobbyManager.create_lobby()

	# Should emit lobby_create_failed since Steam isn't initialized
	assert_signal_emitted(LobbyManager, "lobby_create_failed")


func test_join_lobby_without_steam_emits_failure() -> void:
	# Skip if Steam is actually initialized
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	watch_signals(LobbyManager)

	LobbyManager.join_lobby(12345)

	assert_signal_emitted(LobbyManager, "lobby_join_failed")


func test_leave_lobby_when_not_in_lobby() -> void:
	# Should not crash when leaving while not in a lobby
	LobbyManager.leave_lobby()

	assert_eq(LobbyManager.current_lobby_id, 0, "Should still be 0 after leaving nothing")
	assert_false(LobbyManager.is_host, "Should not be host")


func test_request_lobby_list_without_steam() -> void:
	# Skip if Steam is actually initialized
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	watch_signals(LobbyManager)

	LobbyManager.request_lobby_list()

	# Should emit empty list
	assert_signal_emitted_with_parameters(
		LobbyManager, "lobby_list_received", [[]]
	)


func test_set_lobby_metadata_without_lobby() -> void:
	var result: bool = LobbyManager.set_lobby_metadata("key", "value")
	assert_false(result, "Should fail when not in a lobby")


func test_get_lobby_metadata_without_steam() -> void:
	# Skip if Steam is actually initialized
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	var result: String = LobbyManager.get_lobby_metadata(12345, "server_name")
	assert_eq(result, "", "Should return empty string without Steam")


func test_get_lobby_member_count_without_steam() -> void:
	# Skip if Steam is actually initialized
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	var result: int = LobbyManager.get_lobby_member_count(12345)
	assert_eq(result, 0, "Should return 0 without Steam")


func test_get_lobby_members_without_steam() -> void:
	# Skip if Steam is actually initialized
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	var result: Array[int] = LobbyManager.get_lobby_members(12345)
	assert_eq(result.size(), 0, "Should return empty array without Steam")


func test_get_lobby_owner_without_steam() -> void:
	# Skip if Steam is actually initialized
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	var result: int = LobbyManager.get_lobby_owner(12345)
	assert_eq(result, 0, "Should return 0 without Steam")
