class_name ProceduralFieldGenerator
extends RefCounted
## Generates procedural field content based on a seed and pearl type.
## Creates terrain features, obstacles, and spawns items deterministically.
## The pearl type determines the field's visual theme and item spawn weighting.

## Field size (half-width, so total is 2x this)
const FIELD_HALF_SIZE: float = 18.0

## Minimum distance from center for obstacles (keep spawn area clear)
const CENTER_CLEAR_RADIUS: float = 5.0

## Minimum distance between obstacles
const OBSTACLE_MIN_SPACING: float = 3.0

## Item spawn exclusion radius around obstacles
const ITEM_OBSTACLE_SPACING: float = 2.0


## Theme configuration for a pearl type
class FieldThemeConfig:
	var ground_color: Color
	var obstacle_colors: Dictionary  # String (type) -> Color
	var item_weights: Dictionary  # StringName (item_id) -> int (weight)

	func _init(
		p_ground: Color,
		p_obstacles: Dictionary,
		p_weights: Dictionary
	) -> void:
		ground_color = p_ground
		obstacle_colors = p_obstacles
		item_weights = p_weights


## Cached theme configurations (lazy initialized)
static var _theme_configs_cache: Dictionary = {}


## Get theme configurations dictionary (lazy initialization to avoid static var issues)
static func _get_theme_configs() -> Dictionary:
	if _theme_configs_cache.is_empty():
		_theme_configs_cache = {
			&"flame_pearl": FieldThemeConfig.new(
				Color(0.6, 0.25, 0.15),  # Red-brown ground
				{
					"rock": Color(0.25, 0.22, 0.2),  # Dark charcoal
					"pillar": Color(0.3, 0.25, 0.22),  # Dark grey-brown
					"crystal": Color(0.9, 0.5, 0.2)  # Orange glow
				},
				{
					&"flame_pearl": 3,  # 3x weight
					&"air_pearl": 1,
					&"life_pearl": 1,
					&"water_pearl": 1
				}
			),
			&"air_pearl": FieldThemeConfig.new(
				Color(0.75, 0.78, 0.82),  # White-grey ground
				{
					"rock": Color(0.55, 0.6, 0.7),  # Blue-grey
					"pillar": Color(0.6, 0.65, 0.75),  # Light blue-grey
					"crystal": Color(0.7, 0.85, 1.0)  # Ice blue
				},
				{
					&"flame_pearl": 1,
					&"air_pearl": 3,  # 3x weight
					&"life_pearl": 1,
					&"water_pearl": 1
				}
			),
			&"life_pearl": FieldThemeConfig.new(
				Color(0.35, 0.55, 0.28),  # Green ground
				{
					"rock": Color(0.45, 0.38, 0.28),  # Brown
					"pillar": Color(0.35, 0.42, 0.3),  # Mossy grey-green
					"crystal": Color(0.5, 0.95, 0.4)  # Bright green
				},
				{
					&"flame_pearl": 1,
					&"air_pearl": 1,
					&"life_pearl": 3,  # 3x weight
					&"water_pearl": 1
				}
			),
			&"water_pearl": FieldThemeConfig.new(
				Color(0.25, 0.45, 0.6),  # Blue ground
				{
					"rock": Color(0.7, 0.72, 0.75),  # White-grey
					"pillar": Color(0.65, 0.68, 0.72),  # Light grey
					"crystal": Color(0.5, 0.75, 1.0)  # Light blue
				},
				{
					&"flame_pearl": 1,
					&"air_pearl": 1,
					&"life_pearl": 1,
					&"water_pearl": 3  # 3x weight
				}
			)
		}
	return _theme_configs_cache


var _rng: RandomNumberGenerator
var _seed: int
var _pearl_type: StringName
var _obstacles: Array[Vector3] = []


func _init(generation_seed: int, pearl_type: StringName = &"") -> void:
	_seed = generation_seed
	_pearl_type = pearl_type
	_rng = RandomNumberGenerator.new()
	_rng.seed = generation_seed


## Get the generation seed
func get_seed() -> int:
	return _seed


## Get the pearl type used to generate this field
func get_pearl_type() -> StringName:
	return _pearl_type


## Get the theme configuration for the current pearl type
func _get_theme_config() -> FieldThemeConfig:
	var configs: Dictionary = _get_theme_configs()
	if configs.has(_pearl_type):
		return configs[_pearl_type]
	# Default to flame pearl theme if pearl type is unknown or empty
	return configs.get(&"flame_pearl", null)


## Generate obstacle positions for the field
func generate_obstacles() -> Array[Dictionary]:
	# Reset RNG to ensure deterministic results
	_rng.seed = _seed
	_obstacles.clear()

	var obstacles: Array[Dictionary] = []
	var obstacle_count: int = _rng.randi_range(4, 10)

	for i: int in range(obstacle_count):
		var pos: Vector3 = _find_valid_obstacle_position()
		if pos != Vector3.ZERO:
			_obstacles.append(pos)

			var obstacle_type: String = _pick_obstacle_type()
			var scale_factor: float = _rng.randf_range(0.8, 1.5)
			var rotation_y: float = _rng.randf_range(0, 360)

			obstacles.append({
				"type": obstacle_type,
				"position": pos,
				"scale": scale_factor,
				"rotation_y": rotation_y
			})

	return obstacles


## Generate item spawn data for the field
func generate_items() -> Array[Dictionary]:
	# Use a different seed offset for items to vary independently
	_rng.seed = _seed + 1000

	var items: Array[Dictionary] = []
	var item_count: int = _rng.randi_range(5, 12)

	var item_types: Array[StringName] = _get_item_pool()

	for i: int in range(item_count):
		var pos: Vector3 = _find_valid_item_position()
		if pos == Vector3.ZERO:
			continue

		var item_id: StringName = item_types[_rng.randi() % item_types.size()]
		var quantity: int = _rng.randi_range(1, 3)

		items.append({
			"item_id": item_id,
			"position": pos,
			"quantity": quantity
		})

	return items


## Generate dynamic spawn points for the field
func generate_spawn_points() -> Array[Vector3]:
	# Use a different seed offset for spawn points
	_rng.seed = _seed + 2000

	var spawn_points: Array[Vector3] = []

	# Always have 4 spawn points in a rough circle around center
	var base_radius: float = 3.0
	for i: int in range(4):
		var angle: float = (i * 90.0 + _rng.randf_range(-15, 15)) * PI / 180.0
		var radius: float = base_radius + _rng.randf_range(-0.5, 0.5)
		var pos := Vector3(
			cos(angle) * radius,
			1.0,
			sin(angle) * radius
		)
		spawn_points.append(pos)

	return spawn_points


## Get ground color based on pearl type with slight variation
func get_ground_color() -> Color:
	var config: FieldThemeConfig = _get_theme_config()
	if config == null:
		return Color(0.35, 0.55, 0.3, 1.0)

	_rng.seed = _seed + 4000
	var base: Color = config.ground_color

	# Add slight variation
	return Color(
		base.r + _rng.randf_range(-0.03, 0.03),
		base.g + _rng.randf_range(-0.03, 0.03),
		base.b + _rng.randf_range(-0.03, 0.03),
		1.0
	)


## Get obstacle color based on pearl type and obstacle type
func get_obstacle_color(obstacle_type: String) -> Color:
	var config: FieldThemeConfig = _get_theme_config()
	if config == null or not config.obstacle_colors.has(obstacle_type):
		return Color(0.5, 0.5, 0.5, 1.0)

	_rng.seed = _seed + 5000 + hash(obstacle_type)
	var base: Color = config.obstacle_colors[obstacle_type]

	# Add slight variation
	return Color(
		base.r + _rng.randf_range(-0.05, 0.05),
		base.g + _rng.randf_range(-0.05, 0.05),
		base.b + _rng.randf_range(-0.05, 0.05),
		1.0
	)


# =============================================================================
# Private Helpers
# =============================================================================

func _find_valid_obstacle_position() -> Vector3:
	## Find a position that doesn't overlap with existing obstacles or center.
	for _attempt: int in range(20):
		var pos := Vector3(
			_rng.randf_range(-FIELD_HALF_SIZE + 2, FIELD_HALF_SIZE - 2),
			0.0,
			_rng.randf_range(-FIELD_HALF_SIZE + 2, FIELD_HALF_SIZE - 2)
		)

		# Check center clearance
		if pos.length() < CENTER_CLEAR_RADIUS:
			continue

		# Check spacing from other obstacles
		var valid: bool = true
		for existing: Vector3 in _obstacles:
			if pos.distance_to(existing) < OBSTACLE_MIN_SPACING:
				valid = false
				break

		if valid:
			return pos

	return Vector3.ZERO


func _find_valid_item_position() -> Vector3:
	## Find a position for an item that doesn't overlap with obstacles.
	for _attempt: int in range(20):
		var pos := Vector3(
			_rng.randf_range(-FIELD_HALF_SIZE + 1, FIELD_HALF_SIZE - 1),
			0.0,
			_rng.randf_range(-FIELD_HALF_SIZE + 1, FIELD_HALF_SIZE - 1)
		)

		# Check spacing from obstacles
		var valid: bool = true
		for obstacle: Vector3 in _obstacles:
			if pos.distance_to(obstacle) < ITEM_OBSTACLE_SPACING:
				valid = false
				break

		if valid:
			return pos

	return Vector3.ZERO


func _pick_obstacle_type() -> String:
	var roll: float = _rng.randf()
	if roll < 0.5:
		return "rock"
	elif roll < 0.8:
		return "pillar"
	else:
		return "crystal"


func _get_item_pool() -> Array[StringName]:
	## Get weighted item pool based on pearl type.
	## Items with higher weights appear more frequently.
	var config: FieldThemeConfig = _get_theme_config()
	if config == null:
		# Fallback to equal weights
		return [&"flame_pearl", &"air_pearl", &"life_pearl", &"water_pearl"]

	# Build weighted pool by adding items multiple times based on weight
	var pool: Array[StringName] = []
	for item_id: StringName in config.item_weights:
		var weight: int = config.item_weights[item_id]
		for _w: int in range(weight):
			pool.append(item_id)

	return pool
