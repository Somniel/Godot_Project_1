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


func test_find_field_by_seed_without_steam() -> void:
	# Skip if Steam is actually initialized
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	# Use Array to capture result — lambdas copy local ints by value
	var result: Array[int] = [-1]
	LobbyManager.find_field_by_seed(12345, func(
		lobby_id: int
	) -> void:
		result[0] = lobby_id
	)

	assert_eq(result[0], 0, "Should callback with 0 without Steam")


func test_find_field_by_seed_blocked_by_active_query() -> void:
	# Skip if Steam is actually initialized (can't safely manipulate flags)
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	# Simulate an active find-by-owner query
	LobbyManager._is_finding_lobby = true

	# Use Array to capture result — lambdas copy local ints by value
	var result: Array[int] = [-1]
	LobbyManager.find_field_by_seed(99999, func(
		lobby_id: int
	) -> void:
		result[0] = lobby_id
	)

	assert_eq(
		result[0], 0,
		"Should callback with 0 when another query is active"
	)
	assert_false(
		LobbyManager._is_finding_field,
		"Should not set _is_finding_field when blocked"
	)

	# Clean up
	LobbyManager._is_finding_lobby = false


func test_create_staged_lobby_without_steam() -> void:
	# Skip if Steam is actually initialized
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return

	watch_signals(LobbyManager)

	LobbyManager.create_staged_lobby()

	assert_signal_emitted(LobbyManager, "staged_lobby_failed")


func test_set_staged_metadata_without_staged_lobby() -> void:
	# Should return false when no staged lobby exists
	var result: bool = LobbyManager.set_staged_lobby_metadata(
		"key", "value"
	)
	assert_false(result, "Should fail without a staged lobby")


func test_promote_without_staged_lobby() -> void:
	# Should warn and not change current_lobby_id
	var before: int = LobbyManager.current_lobby_id
	LobbyManager.promote_staged_lobby()
	assert_eq(
		LobbyManager.current_lobby_id, before,
		"Should not change current_lobby_id without staged lobby"
	)
	# push_warning is tracked as engine error in editor but not headless;
	# mark any tracked errors as handled so neither environment fails.
	for err: Variant in get_errors():
		err.handled = true


func test_abandon_staged_lobby_without_lobby() -> void:
	# Should be a safe no-op
	LobbyManager.abandon_staged_lobby()
	assert_eq(
		LobbyManager._staged_lobby_id, 0,
		"Should remain 0 after abandon with no staged lobby"
	)
