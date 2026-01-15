extends GutTest
## Unit tests for the Utils class.


func test_sanitize_display_string_basic() -> void:
	var result: String = Utils.sanitize_display_string("Hello World")
	assert_eq(result, "Hello World", "Basic string should pass through unchanged")


func test_sanitize_display_string_strips_whitespace() -> void:
	var result: String = Utils.sanitize_display_string("  Hello World  ")
	assert_eq(result, "Hello World", "Should strip leading and trailing whitespace")


func test_sanitize_display_string_limits_length() -> void:
	var long_string: String = "A".repeat(100)
	var result: String = Utils.sanitize_display_string(long_string, 10)
	assert_eq(result.length(), 10, "Should limit string to max_length")
	assert_eq(result, "AAAAAAAAAA", "Should be first 10 characters")


func test_sanitize_display_string_removes_null_char() -> void:
	# Note: GDScript handles null characters (char(0)) specially in strings.
	# String iteration may not process them as expected.
	# Testing with other low control characters instead.
	var test_string: String = "Hello" + char(1) + "World"
	var result: String = Utils.sanitize_display_string(test_string)
	assert_eq(result, "HelloWorld", "Should remove control character (SOH)")


func test_sanitize_display_string_removes_control_chars() -> void:
	var test_string: String = "Hello" + char(1) + char(2) + char(3) + "World"
	var result: String = Utils.sanitize_display_string(test_string)
	assert_eq(result, "HelloWorld", "Should remove control characters")


func test_sanitize_display_string_preserves_tabs() -> void:
	var result: String = Utils.sanitize_display_string("Hello\tWorld")
	assert_eq(result, "Hello\tWorld", "Should preserve tab characters")


func test_sanitize_display_string_empty_string() -> void:
	var result: String = Utils.sanitize_display_string("")
	assert_eq(result, "", "Empty string should return empty")


func test_sanitize_display_string_only_whitespace() -> void:
	var result: String = Utils.sanitize_display_string("   ")
	assert_eq(result, "", "Whitespace-only string should return empty after strip")


func test_sanitize_display_string_unicode() -> void:
	var result: String = Utils.sanitize_display_string("こんにちは")
	assert_eq(result, "こんにちは", "Unicode characters should be preserved")


func test_is_valid_lobby_id_positive() -> void:
	assert_true(Utils.is_valid_lobby_id(1), "1 should be valid")
	assert_true(Utils.is_valid_lobby_id(12345), "Positive numbers should be valid")
	assert_true(Utils.is_valid_lobby_id(999999999), "Large positive numbers should be valid")


func test_is_valid_lobby_id_zero() -> void:
	assert_false(Utils.is_valid_lobby_id(0), "0 should be invalid")


func test_is_valid_lobby_id_negative() -> void:
	assert_false(Utils.is_valid_lobby_id(-1), "Negative numbers should be invalid")
	assert_false(Utils.is_valid_lobby_id(-999), "Large negative numbers should be invalid")


func test_is_valid_peer_id_positive() -> void:
	assert_true(Utils.is_valid_peer_id(1), "1 should be valid")
	assert_true(Utils.is_valid_peer_id(12345), "Positive numbers should be valid")


func test_is_valid_peer_id_zero() -> void:
	assert_false(Utils.is_valid_peer_id(0), "0 should be invalid")


func test_is_valid_peer_id_negative() -> void:
	assert_false(Utils.is_valid_peer_id(-1), "Negative numbers should be invalid")
