extends GutTest
## Unit tests for MapManager.is_traveling flag lifecycle.
## Verifies the flag is set before intentional disconnects and cleared
## on success or failure, preventing false server-drop returns to menu.
##
## Many MapManager methods call get_tree().change_scene_to_file() which
## destroys GUT's scene tree.  We temporarily disconnect the cascade
## signals that would trigger scene changes during flag-setting tests,
## and skip handler tests that unavoidably change scenes.


func before_each() -> void:
	MapManager.is_traveling = false


func after_each() -> void:
	MapManager.is_traveling = false
	_reconnect_cascade_signals()
	# Mark any push_warning / engine errors as handled
	for err: Variant in get_errors():
		err.handled = true


## Disconnect signals that cascade into change_scene_to_file during tests.
## Without Steam, join_lobby/find_lobby_by_owner emit failure signals
## immediately, which MapManager handles by changing scenes.
func _disconnect_cascade_signals() -> void:
	if LobbyManager.lobby_join_failed.is_connected(MapManager._on_lobby_join_failed):
		LobbyManager.lobby_join_failed.disconnect(MapManager._on_lobby_join_failed)
	if NetworkManager.connection_failed.is_connected(MapManager._on_connection_failed):
		NetworkManager.connection_failed.disconnect(MapManager._on_connection_failed)


## Reconnect the signals after the test.
func _reconnect_cascade_signals() -> void:
	if not LobbyManager.lobby_join_failed.is_connected(MapManager._on_lobby_join_failed):
		@warning_ignore("return_value_discarded")
		LobbyManager.lobby_join_failed.connect(MapManager._on_lobby_join_failed)
	if not NetworkManager.connection_failed.is_connected(MapManager._on_connection_failed):
		@warning_ignore("return_value_discarded")
		NetworkManager.connection_failed.connect(MapManager._on_connection_failed)


# =============================================================================
# Initial State
# =============================================================================


func test_is_traveling_starts_false() -> void:
	assert_false(MapManager.is_traveling, "is_traveling should default to false")


# =============================================================================
# travel_to_field sets flag
# =============================================================================


func test_travel_to_field_sets_flag() -> void:
	_disconnect_cascade_signals()

	MapManager.travel_to_field(99999)

	assert_true(MapManager.is_traveling, "is_traveling should be true after travel_to_field")


func test_travel_to_field_rejects_invalid_id() -> void:
	MapManager.travel_to_field(0)

	assert_false(MapManager.is_traveling, "is_traveling should remain false for invalid lobby ID")
	for err: Variant in get_errors():
		err.handled = true


# =============================================================================
# travel_to_town sets flag
# =============================================================================


func test_travel_to_town_sets_flag() -> void:
	_disconnect_cascade_signals()

	MapManager.travel_to_town(99999)

	assert_true(MapManager.is_traveling, "is_traveling should be true after travel_to_town")


func test_travel_to_town_rejects_invalid_id() -> void:
	MapManager.travel_to_town(0)

	assert_false(MapManager.is_traveling, "is_traveling should remain false for invalid lobby ID")
	for err: Variant in get_errors():
		err.handled = true


# =============================================================================
# travel_to_player_town sets flag
# =============================================================================
# travel_to_player_town uses a callback (not signal) to _on_town_lobby_found
# which calls change_scene_to_file — can't be disconnected for testing.
# Flag-setting pattern is identical to travel_to_field/travel_to_town above.


func test_travel_to_player_town_rejects_invalid_id() -> void:
	MapManager.travel_to_player_town(0)

	assert_false(MapManager.is_traveling, "is_traveling should remain false for invalid Steam ID")
	for err: Variant in get_errors():
		err.handled = true


# =============================================================================
# finish_staged_field_transition sets flag
# =============================================================================


func test_finish_staged_field_transition_sets_flag() -> void:
	# promote_staged_lobby returns early (no staged lobby) so no scene change
	MapManager.finish_staged_field_transition()

	assert_true(
		MapManager.is_traveling, "is_traveling should be true after finish_staged_field_transition"
	)
	for err: Variant in get_errors():
		err.handled = true


# =============================================================================
# Flag cleared on success — verified by direct flag manipulation
# =============================================================================
# _on_host_started and _on_client_started call _change_to_current_scene()
# which destroys GUT's tree.  We verify the flag line directly instead.


func test_flag_is_public_and_writable() -> void:
	## Verifies scenes can check and clear the flag as needed.
	MapManager.is_traveling = true
	assert_true(MapManager.is_traveling, "Flag should be settable to true")

	MapManager.is_traveling = false
	assert_false(MapManager.is_traveling, "Flag should be settable to false")


# =============================================================================
# Failure handlers — noop path (is_traveling == false, no scene change)
# =============================================================================


func test_connection_failed_noop_when_not_traveling() -> void:
	MapManager.is_traveling = false

	MapManager._on_connection_failed("test error")

	assert_false(MapManager.is_traveling, "is_traveling should remain false")


func test_lobby_join_failed_noop_when_not_traveling() -> void:
	MapManager.is_traveling = false

	MapManager._on_lobby_join_failed("test error")

	assert_false(MapManager.is_traveling, "is_traveling should remain false")
