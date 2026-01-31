extends GutTest
## Tests for FieldTownLinker._parse_linked_lobby_id static utility.


func test_parse_lobby_id_from_string() -> void:
	var dict: Dictionary = {"linked_lobby_id": "123456"}
	var result: int = FieldTownLinker._parse_linked_lobby_id(dict)
	assert_eq(result, 123456, "Should parse string lobby ID")


func test_parse_lobby_id_from_int() -> void:
	var dict: Dictionary = {"linked_lobby_id": 42}
	var result: int = FieldTownLinker._parse_linked_lobby_id(dict)
	assert_eq(result, 42, "Should parse int lobby ID")


func test_parse_lobby_id_from_float() -> void:
	var dict: Dictionary = {"linked_lobby_id": 42.0}
	var result: int = FieldTownLinker._parse_linked_lobby_id(dict)
	assert_eq(result, 42, "Should parse float lobby ID as int")


func test_parse_lobby_id_missing_key_returns_zero() -> void:
	var dict: Dictionary = {}
	var result: int = FieldTownLinker._parse_linked_lobby_id(dict)
	assert_eq(result, 0, "Should return 0 when key missing")


func test_parse_lobby_id_from_string_zero() -> void:
	var dict: Dictionary = {"linked_lobby_id": "0"}
	var result: int = FieldTownLinker._parse_linked_lobby_id(dict)
	assert_eq(result, 0, "Should parse '0' as 0")
