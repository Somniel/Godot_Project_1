extends Node
## Manages UI state to coordinate input blocking across the game.
## UIs that should block player input register/unregister when shown/hidden.

## Emitted when blocking UI state changes (true = at least one blocking UI open)
signal blocking_ui_changed(is_blocking: bool)

var _blocking_ui_count: int = 0


func register_blocking_ui() -> void:
	## Register a blocking UI as opened. Call when showing a UI that should block input.
	_blocking_ui_count += 1
	if _blocking_ui_count == 1:
		blocking_ui_changed.emit(true)


func unregister_blocking_ui() -> void:
	## Unregister a blocking UI as closed. Call when hiding a blocking UI.
	_blocking_ui_count = max(0, _blocking_ui_count - 1)
	if _blocking_ui_count == 0:
		blocking_ui_changed.emit(false)


func is_any_ui_blocking() -> bool:
	## Check if any blocking UI is currently open.
	return _blocking_ui_count > 0


func reset() -> void:
	## Reset the blocking count. Use when changing scenes to prevent stuck state.
	_blocking_ui_count = 0
