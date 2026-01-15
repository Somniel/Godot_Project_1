extends GutTest
## Unit tests for SteamManager autoload.


func test_app_id_from_environment() -> void:
	# APP_ID should be loaded from STEAM_APP_ID environment variable
	var env_app_id: String = OS.get_environment("STEAM_APP_ID")
	if env_app_id.is_empty():
		# If env var not set, APP_ID should be 0 (uninitialized)
		assert_eq(SteamManager.APP_ID, 0, "APP_ID should be 0 when env var not set")
	else:
		assert_eq(SteamManager.APP_ID, env_app_id.to_int(), "APP_ID should match env var")


func test_get_steam_id_returns_int() -> void:
	var result: int = SteamManager.get_steam_id()
	# Result depends on whether Steam is initialized
	assert_typeof(result, TYPE_INT, "Should return an integer")


func test_get_steam_username_returns_string() -> void:
	var result: String = SteamManager.get_steam_username()
	assert_typeof(result, TYPE_STRING, "Should return a string")


func test_get_steam_without_init() -> void:
	# If Steam failed to init, should return null
	if SteamManager.is_steam_initialized:
		pending("Steam is initialized, skipping offline test")
		return
	var result: Object = SteamManager.get_steam()
	assert_null(result, "Should return null when not initialized")


func test_get_steam_with_init() -> void:
	# If Steam is initialized, should return the singleton
	if not SteamManager.is_steam_initialized:
		pending("Steam is not initialized, skipping online test")
		return
	var result: Object = SteamManager.get_steam()
	assert_not_null(result, "Should return Steam singleton when initialized")


func test_init_attempted_flag() -> void:
	# After _ready runs, init should have been attempted
	assert_true(SteamManager.init_attempted, "Init should have been attempted")
