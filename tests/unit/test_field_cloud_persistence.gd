extends GutTest
## Tests for FieldCloudPersistence static parsing utilities.


# =============================================================================
# parse_position
# =============================================================================

func test_parse_position_from_vector3() -> void:
	var input: Vector3 = Vector3(1.5, 2.0, -3.5)
	var result: Vector3 = FieldCloudPersistence.parse_position(input)
	assert_eq(result, Vector3(1.5, 2.0, -3.5), "Should pass through Vector3")


func test_parse_position_from_dictionary() -> void:
	var input: Dictionary = {"x": 1.0, "y": 2.0, "z": 3.0}
	var result: Vector3 = FieldCloudPersistence.parse_position(input)
	assert_eq(result, Vector3(1.0, 2.0, 3.0), "Should parse from dict")


func test_parse_position_from_dictionary_partial() -> void:
	var input: Dictionary = {"x": 5.0}
	var result: Vector3 = FieldCloudPersistence.parse_position(input)
	assert_eq(result, Vector3(5.0, 0.0, 0.0), "Should default missing axes to 0")


func test_parse_position_from_string() -> void:
	var result: Vector3 = FieldCloudPersistence.parse_position("(1.5, 2.0, -3.5)")
	assert_almost_eq(result.x, 1.5, 0.01, "X should be 1.5")
	assert_almost_eq(result.y, 2.0, 0.01, "Y should be 2.0")
	assert_almost_eq(result.z, -3.5, 0.01, "Z should be -3.5")


func test_parse_position_from_null_returns_zero() -> void:
	var result: Vector3 = FieldCloudPersistence.parse_position(null)
	assert_eq(result, Vector3.ZERO, "Null should return Vector3.ZERO")


func test_parse_position_from_invalid_type_returns_zero() -> void:
	var result: Vector3 = FieldCloudPersistence.parse_position(42)
	assert_eq(result, Vector3.ZERO, "Int should return Vector3.ZERO")


# =============================================================================
# parse_steam_id
# =============================================================================

func test_parse_steam_id_from_string() -> void:
	var result: int = FieldCloudPersistence.parse_steam_id("76561198012345678")
	assert_eq(result, 76561198012345678, "Should parse string Steam ID")


func test_parse_steam_id_from_int() -> void:
	var result: int = FieldCloudPersistence.parse_steam_id(12345)
	assert_eq(result, 12345, "Should pass through int")


func test_parse_steam_id_from_float() -> void:
	var result: int = FieldCloudPersistence.parse_steam_id(12345.0)
	assert_eq(result, 12345, "Should truncate float to int")


func test_parse_steam_id_from_null_returns_zero() -> void:
	var result: int = FieldCloudPersistence.parse_steam_id(null)
	assert_eq(result, 0, "Null should return 0")


func test_parse_steam_id_from_empty_string_returns_zero() -> void:
	var result: int = FieldCloudPersistence.parse_steam_id("")
	assert_eq(result, 0, "Empty string should return 0")


# =============================================================================
# parse_vector3_string
# =============================================================================

func test_parse_vector3_string_valid() -> void:
	var result: Vector3 = FieldCloudPersistence.parse_vector3_string("(1, 2, 3)")
	assert_almost_eq(result.x, 1.0, 0.01, "X should be 1")
	assert_almost_eq(result.y, 2.0, 0.01, "Y should be 2")
	assert_almost_eq(result.z, 3.0, 0.01, "Z should be 3")


func test_parse_vector3_string_with_spaces() -> void:
	var result: Vector3 = FieldCloudPersistence.parse_vector3_string("( 1.5 , -2.0 , 3.0 )")
	assert_almost_eq(result.x, 1.5, 0.01, "X should be 1.5")
	assert_almost_eq(result.y, -2.0, 0.01, "Y should be -2.0")
	assert_almost_eq(result.z, 3.0, 0.01, "Z should be 3.0")


func test_parse_vector3_string_no_parens_returns_zero() -> void:
	var result: Vector3 = FieldCloudPersistence.parse_vector3_string("1, 2, 3")
	assert_eq(result, Vector3.ZERO, "No parens should return ZERO")


func test_parse_vector3_string_wrong_part_count_returns_zero() -> void:
	var result: Vector3 = FieldCloudPersistence.parse_vector3_string("(1, 2)")
	assert_eq(result, Vector3.ZERO, "Two parts should return ZERO")


func test_parse_vector3_string_empty_returns_zero() -> void:
	var result: Vector3 = FieldCloudPersistence.parse_vector3_string("")
	assert_eq(result, Vector3.ZERO, "Empty string should return ZERO")
