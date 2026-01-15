class_name Utils
## Shared utility functions for the project.


## Sanitizes user-provided strings for safe display.
## Limits length, removes leading/trailing whitespace, and removes control characters.
static func sanitize_display_string(text: String, max_length: int = 64) -> String:
	# Remove control characters (ASCII 0-31 except common whitespace)
	var sanitized: String = ""
	for i in range(text.length()):
		var c: String = text[i]
		var code: int = c.unicode_at(0)
		# Allow printable characters and common whitespace (space, tab)
		if code >= 32 or code == 9:
			sanitized += c

	return sanitized.substr(0, max_length).strip_edges()


## Validates that a lobby ID is potentially valid (non-zero positive).
static func is_valid_lobby_id(lobby_id: int) -> bool:
	return lobby_id > 0


## Validates that a peer ID is potentially valid (positive).
static func is_valid_peer_id(peer_id: int) -> bool:
	return peer_id > 0
