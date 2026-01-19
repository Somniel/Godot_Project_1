extends Node
## Manages Steam initialization, shutdown, and identity.
## This autoload handles all direct Steam API interactions for authentication.

signal steam_initialized
signal steam_init_failed(reason: String)

## Steam App ID - Set via STEAM_APP_ID environment variable
var APP_ID: int = 0

var is_steam_initialized: bool = false
var init_attempted: bool = false
var init_error: String = ""
var steam_id: int = 0
var steam_username: String = ""


func _init() -> void:
	# Load App ID from ProjectSettings (can be overridden via override.cfg)
	# Falls back to environment variable for CI/production builds
	var project_app_id: int = ProjectSettings.get_setting("steam/initialization/app_id", 0)

	if project_app_id > 0:
		APP_ID = project_app_id
	else:
		# Fall back to environment variable
		var env_app_id: String = OS.get_environment("STEAM_APP_ID")
		if env_app_id.is_empty() or not env_app_id.is_valid_int():
			push_warning("SteamManager: No Steam App ID configured. Set steam/initialization/app_id in override.cfg or STEAM_APP_ID environment variable.")
			return
		APP_ID = env_app_id.to_int()

	# Set environment variables before Steam initializes (required for editor testing)
	OS.set_environment("SteamAppId", str(APP_ID))
	OS.set_environment("SteamGameId", str(APP_ID))


func _ready() -> void:
	_initialize_steam()


func _initialize_steam() -> void:
	init_attempted = true

	# Check if GodotSteam is available
	if not Engine.has_singleton("Steam"):
		init_error = "GodotSteam extension not installed"
		push_warning("SteamManager: GodotSteam extension not found")
		steam_init_failed.emit(init_error)
		return

	var steam: Object = Engine.get_singleton("Steam")

	# Initialize Steam with our app ID
	# GDExtension singletons require dynamic dispatch - suppress expected warnings
	# steamInitEx(app_id, embed_callbacks) - we handle callbacks manually in _process
	@warning_ignore("unsafe_method_access")
	var init_result: Dictionary = steam.steamInitEx(APP_ID, false)

	# Check initialization status
	# Status 0 = OK, 1 = Failed, 2 = No client, etc.
	var status: int = init_result.get("status", -1)
	var verbal: String = init_result.get("verbal", "Unknown error")

	if status != 0:
		init_error = verbal
		push_warning("SteamManager: Steam init failed - %s" % verbal)
		steam_init_failed.emit(verbal)
		return

	# Steam initialized successfully
	is_steam_initialized = true
	@warning_ignore("unsafe_method_access")
	steam_id = steam.getSteamID()
	@warning_ignore("unsafe_method_access")
	steam_username = steam.getPersonaName()

	print("SteamManager: Initialized successfully")
	print("SteamManager: Logged in as %s (ID: %s)" % [steam_username, steam_id])

	steam_initialized.emit()


func _process(_delta: float) -> void:
	if is_steam_initialized:
		@warning_ignore("unsafe_method_access")
		Engine.get_singleton("Steam").run_callbacks()


func _exit_tree() -> void:
	if is_steam_initialized:
		print("SteamManager: Shutting down Steam")
		@warning_ignore("unsafe_method_access")
		Engine.get_singleton("Steam").steamShutdown()


func get_steam_id() -> int:
	return steam_id


func get_steam_username() -> String:
	return steam_username


func get_steam() -> Object:
	## Returns the Steam singleton for direct API access.
	## Returns null if Steam is not initialized.
	if is_steam_initialized:
		return Engine.get_singleton("Steam")
	return null
