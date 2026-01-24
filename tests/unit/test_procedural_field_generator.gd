extends GutTest
## Unit tests for ProceduralFieldGenerator.
## Tests theme selection, deterministic generation, and weighted item spawning.


# =============================================================================
# Theme Selection Tests
# =============================================================================

func test_flame_pearl_returns_flame_theme() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"flame_pearl")
	var ground_color: Color = generator.get_ground_color()

	# Flame theme has red-brown ground (approximately 0.6, 0.25, 0.15)
	assert_almost_eq(ground_color.r, 0.6, 0.1, "Ground red should be ~0.6")
	assert_almost_eq(ground_color.g, 0.25, 0.1, "Ground green should be ~0.25")
	assert_almost_eq(ground_color.b, 0.15, 0.1, "Ground blue should be ~0.15")


func test_air_pearl_returns_air_theme() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"air_pearl")
	var ground_color: Color = generator.get_ground_color()

	# Air theme has white-grey ground (approximately 0.75, 0.78, 0.82)
	assert_almost_eq(ground_color.r, 0.75, 0.1, "Ground red should be ~0.75")
	assert_almost_eq(ground_color.g, 0.78, 0.1, "Ground green should be ~0.78")
	assert_almost_eq(ground_color.b, 0.82, 0.1, "Ground blue should be ~0.82")


func test_life_pearl_returns_life_theme() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"life_pearl")
	var ground_color: Color = generator.get_ground_color()

	# Life theme has green ground (approximately 0.35, 0.55, 0.28)
	assert_almost_eq(ground_color.r, 0.35, 0.1, "Ground red should be ~0.35")
	assert_almost_eq(ground_color.g, 0.55, 0.1, "Ground green should be ~0.55")
	assert_almost_eq(ground_color.b, 0.28, 0.1, "Ground blue should be ~0.28")


func test_water_pearl_returns_water_theme() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"water_pearl")
	var ground_color: Color = generator.get_ground_color()

	# Water theme has blue ground (approximately 0.25, 0.45, 0.6)
	assert_almost_eq(ground_color.r, 0.25, 0.1, "Ground red should be ~0.25")
	assert_almost_eq(ground_color.g, 0.45, 0.1, "Ground green should be ~0.45")
	assert_almost_eq(ground_color.b, 0.6, 0.1, "Ground blue should be ~0.6")


func test_unknown_pearl_defaults_to_flame_theme() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"unknown_pearl")
	var ground_color: Color = generator.get_ground_color()

	# Should default to flame theme (red-brown ground)
	assert_almost_eq(ground_color.r, 0.6, 0.1, "Unknown pearl should default to flame theme")


func test_empty_pearl_defaults_to_flame_theme() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"")
	var ground_color: Color = generator.get_ground_color()

	# Should default to flame theme (red-brown ground)
	assert_almost_eq(ground_color.r, 0.6, 0.1, "Empty pearl should default to flame theme")


# =============================================================================
# Obstacle Color Tests
# =============================================================================

func test_obstacle_colors_match_theme() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"flame_pearl")

	var rock_color: Color = generator.get_obstacle_color("rock")
	var crystal_color: Color = generator.get_obstacle_color("crystal")

	# Flame theme: rock is dark charcoal (~0.25), crystal is orange (~0.9, 0.5, 0.2)
	assert_almost_eq(rock_color.r, 0.25, 0.1, "Rock should be dark")
	assert_almost_eq(crystal_color.r, 0.9, 0.1, "Crystal should be orange-ish")


func test_obstacle_color_unknown_type_returns_grey() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"flame_pearl")
	var color: Color = generator.get_obstacle_color("unknown_type")

	# Should return default grey (0.5, 0.5, 0.5)
	assert_almost_eq(color.r, 0.5, 0.01, "Unknown type should return grey")
	assert_almost_eq(color.g, 0.5, 0.01, "Unknown type should return grey")
	assert_almost_eq(color.b, 0.5, 0.01, "Unknown type should return grey")


# =============================================================================
# Deterministic Generation Tests
# =============================================================================

func test_same_seed_produces_same_obstacles() -> void:
	var gen_a := ProceduralFieldGenerator.new(42, &"flame_pearl")
	var gen_b := ProceduralFieldGenerator.new(42, &"flame_pearl")

	var obstacles_a: Array[Dictionary] = gen_a.generate_obstacles()
	var obstacles_b: Array[Dictionary] = gen_b.generate_obstacles()

	assert_eq(obstacles_a.size(), obstacles_b.size(), "Same seed should produce same obstacle count")

	for i: int in range(obstacles_a.size()):
		assert_eq(
			obstacles_a[i]["type"],
			obstacles_b[i]["type"],
			"Obstacle types should match"
		)
		assert_eq(
			obstacles_a[i]["position"],
			obstacles_b[i]["position"],
			"Obstacle positions should match"
		)


func test_same_seed_produces_same_items() -> void:
	var gen_a := ProceduralFieldGenerator.new(42, &"flame_pearl")
	var gen_b := ProceduralFieldGenerator.new(42, &"flame_pearl")

	# Generate obstacles first (required for item placement)
	gen_a.generate_obstacles()
	gen_b.generate_obstacles()

	var items_a: Array[Dictionary] = gen_a.generate_items()
	var items_b: Array[Dictionary] = gen_b.generate_items()

	assert_eq(items_a.size(), items_b.size(), "Same seed should produce same item count")

	for i: int in range(items_a.size()):
		assert_eq(
			items_a[i]["item_id"],
			items_b[i]["item_id"],
			"Item IDs should match"
		)
		assert_eq(
			items_a[i]["position"],
			items_b[i]["position"],
			"Item positions should match"
		)


func test_different_seeds_produce_different_results() -> void:
	var gen_a := ProceduralFieldGenerator.new(100, &"flame_pearl")
	var gen_b := ProceduralFieldGenerator.new(200, &"flame_pearl")

	var obstacles_a: Array[Dictionary] = gen_a.generate_obstacles()
	var obstacles_b: Array[Dictionary] = gen_b.generate_obstacles()

	# Different seeds should produce different results
	# (There's a tiny chance they could match, but practically won't)
	var any_different: bool = false
	if obstacles_a.size() != obstacles_b.size():
		any_different = true
	else:
		for i: int in range(obstacles_a.size()):
			if obstacles_a[i]["position"] != obstacles_b[i]["position"]:
				any_different = true
				break

	assert_true(any_different, "Different seeds should produce different results")


func test_same_seed_different_pearl_produces_same_layout() -> void:
	# Same seed should produce same positions regardless of pearl type
	# Only colors and item weights should differ
	var gen_flame := ProceduralFieldGenerator.new(42, &"flame_pearl")
	var gen_water := ProceduralFieldGenerator.new(42, &"water_pearl")

	var obstacles_flame: Array[Dictionary] = gen_flame.generate_obstacles()
	var obstacles_water: Array[Dictionary] = gen_water.generate_obstacles()

	assert_eq(
		obstacles_flame.size(),
		obstacles_water.size(),
		"Same seed should produce same obstacle count regardless of pearl"
	)

	for i: int in range(obstacles_flame.size()):
		assert_eq(
			obstacles_flame[i]["position"],
			obstacles_water[i]["position"],
			"Obstacle positions should match regardless of pearl"
		)


# =============================================================================
# Item Pool Weighting Tests
# =============================================================================

func test_flame_pearl_favors_flame_items() -> void:
	# Generate many items and check distribution
	var flame_count: int = 0
	var total_count: int = 0

	# Run multiple generations to get statistical significance
	for seed_offset: int in range(100):
		var generator := ProceduralFieldGenerator.new(seed_offset, &"flame_pearl")
		generator.generate_obstacles()
		var items: Array[Dictionary] = generator.generate_items()

		for item: Dictionary in items:
			total_count += 1
			if item["item_id"] == &"flame_pearl":
				flame_count += 1

	# With 3x weighting, flame pearls should be ~50% (3/6 of pool)
	# Allow some variance but it should be significantly above 25% (equal distribution)
	var flame_ratio: float = float(flame_count) / float(total_count)
	assert_gt(flame_ratio, 0.35, "Flame fields should favor flame pearl spawns (got %.1f%%)" % [
		flame_ratio * 100
	])


func test_water_pearl_favors_water_items() -> void:
	var water_count: int = 0
	var total_count: int = 0

	for seed_offset: int in range(100):
		var generator := ProceduralFieldGenerator.new(seed_offset, &"water_pearl")
		generator.generate_obstacles()
		var items: Array[Dictionary] = generator.generate_items()

		for item: Dictionary in items:
			total_count += 1
			if item["item_id"] == &"water_pearl":
				water_count += 1

	var water_ratio: float = float(water_count) / float(total_count)
	assert_gt(water_ratio, 0.35, "Water fields should favor water pearl spawns (got %.1f%%)" % [
		water_ratio * 100
	])


# =============================================================================
# Spawn Point Tests
# =============================================================================

func test_spawn_points_returns_four_points() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"flame_pearl")
	var spawn_points: Array[Vector3] = generator.generate_spawn_points()

	assert_eq(spawn_points.size(), 4, "Should generate exactly 4 spawn points")


func test_spawn_points_are_near_center() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"flame_pearl")
	var spawn_points: Array[Vector3] = generator.generate_spawn_points()

	for point: Vector3 in spawn_points:
		var distance: float = Vector3(point.x, 0, point.z).length()
		assert_lt(distance, 5.0, "Spawn points should be within 5 units of center")


func test_spawn_points_are_deterministic() -> void:
	var gen_a := ProceduralFieldGenerator.new(42, &"flame_pearl")
	var gen_b := ProceduralFieldGenerator.new(42, &"flame_pearl")

	var spawns_a: Array[Vector3] = gen_a.generate_spawn_points()
	var spawns_b: Array[Vector3] = gen_b.generate_spawn_points()

	for i: int in range(4):
		assert_eq(spawns_a[i], spawns_b[i], "Spawn points should be deterministic")


# =============================================================================
# Getter Tests
# =============================================================================

func test_get_seed_returns_seed() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"flame_pearl")
	assert_eq(generator.get_seed(), 12345, "Should return the generation seed")


func test_get_pearl_type_returns_pearl_type() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"water_pearl")
	assert_eq(generator.get_pearl_type(), &"water_pearl", "Should return the pearl type")


# =============================================================================
# Obstacle Generation Tests
# =============================================================================

func test_obstacles_count_in_range() -> void:
	# Run multiple times to verify count range
	for seed_val: int in range(20):
		var generator := ProceduralFieldGenerator.new(seed_val, &"flame_pearl")
		var obstacles: Array[Dictionary] = generator.generate_obstacles()

		assert_gte(obstacles.size(), 0, "Should have at least 0 obstacles")
		assert_lte(obstacles.size(), 10, "Should have at most 10 obstacles")


func test_obstacles_outside_center_radius() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"flame_pearl")
	var obstacles: Array[Dictionary] = generator.generate_obstacles()

	for obstacle: Dictionary in obstacles:
		var pos: Vector3 = obstacle["position"]
		var distance: float = Vector3(pos.x, 0, pos.z).length()
		assert_gt(distance, 4.0, "Obstacles should be outside center clear radius")


func test_obstacles_have_valid_types() -> void:
	var valid_types: Array[String] = ["rock", "pillar", "crystal"]

	for seed_val: int in range(10):
		var generator := ProceduralFieldGenerator.new(seed_val, &"flame_pearl")
		var obstacles: Array[Dictionary] = generator.generate_obstacles()

		for obstacle: Dictionary in obstacles:
			assert_has(valid_types, obstacle["type"], "Obstacle type should be valid")


func test_obstacles_have_scale_and_rotation() -> void:
	var generator := ProceduralFieldGenerator.new(12345, &"flame_pearl")
	var obstacles: Array[Dictionary] = generator.generate_obstacles()

	for obstacle: Dictionary in obstacles:
		assert_has(obstacle, "scale", "Obstacle should have scale")
		assert_has(obstacle, "rotation_y", "Obstacle should have rotation_y")
		assert_gte(obstacle["scale"], 0.8, "Scale should be >= 0.8")
		assert_lte(obstacle["scale"], 1.5, "Scale should be <= 1.5")
