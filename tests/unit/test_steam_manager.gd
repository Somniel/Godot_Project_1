extends GutTest
## Unit tests for SteamManager autoload.


func test_app_id_configured() -> void:
	# APP_ID should be loaded from project settings or STEAM_APP_ID environment variable
	var project_app_id: int = ProjectSettings.get_setting("steam/initialization/app_id", 0)
	var env_app_id: String = OS.get_environment("STEAM_APP_ID")

	if project_app_id > 0:
		# Project settings takes priority
		assert_eq(SteamManager.APP_ID, project_app_id, "APP_ID should match project settings")
	elif not env_app_id.is_empty():
		# Fall back to environment variable
		assert_eq(SteamManager.APP_ID, env_app_id.to_int(), "APP_ID should match env var")
	else:
		# Neither configured - should be 0
		assert_eq(SteamManager.APP_ID, 0, "APP_ID should be 0 when not configured")


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
