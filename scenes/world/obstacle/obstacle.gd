class_name FieldObstacle
extends StaticBody3D
## A procedurally placed obstacle in a field.
## Can be configured as rock, pillar, or crystal.

enum ObstacleType { ROCK, PILLAR, CRYSTAL }

@export var obstacle_type: ObstacleType = ObstacleType.ROCK

@onready var _mesh_instance: MeshInstance3D = $MeshInstance3D
@onready var _collision_shape: CollisionShape3D = $CollisionShape3D

var _material: StandardMaterial3D
var _custom_color: Color = Color.WHITE
var _has_custom_color: bool = false


func _ready() -> void:
	_apply_type()


## Configure the obstacle type and visual properties.
## If custom_color is provided, it overrides the default color for this obstacle type.
func setup(
	type_name: String,
	scale_factor: float,
	rotation_y_deg: float,
	custom_color: Color = Color.WHITE
) -> void:
	match type_name:
		"rock":
			obstacle_type = ObstacleType.ROCK
		"pillar":
			obstacle_type = ObstacleType.PILLAR
		"crystal":
			obstacle_type = ObstacleType.CRYSTAL
		_:
			obstacle_type = ObstacleType.ROCK

	# Check if a custom color was provided (not default white)
	if custom_color != Color.WHITE:
		_custom_color = custom_color
		_has_custom_color = true
	else:
		_has_custom_color = false

	scale = Vector3(scale_factor, scale_factor, scale_factor)
	rotation_degrees.y = rotation_y_deg

	# Apply type after setting properties (deferred if not ready yet)
	if is_inside_tree():
		_apply_type()


func _apply_type() -> void:
	if _mesh_instance == null or _collision_shape == null:
		return

	_material = StandardMaterial3D.new()

	match obstacle_type:
		ObstacleType.ROCK:
			_setup_rock()
		ObstacleType.PILLAR:
			_setup_pillar()
		ObstacleType.CRYSTAL:
			_setup_crystal()


func _setup_rock() -> void:
	# Rock: irregular rounded shape (sphere-ish)
	var mesh := SphereMesh.new()
	mesh.radius = 0.8
	mesh.height = 1.4
	_mesh_instance.mesh = mesh

	var shape := SphereShape3D.new()
	shape.radius = 0.8
	_collision_shape.shape = shape

	if _has_custom_color:
		_material.albedo_color = _custom_color
	else:
		_material.albedo_color = Color(0.45, 0.42, 0.38)
	_material.roughness = 0.9
	_mesh_instance.material_override = _material


func _setup_pillar() -> void:
	# Pillar: tall cylinder
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.4
	mesh.bottom_radius = 0.5
	mesh.height = 2.5
	_mesh_instance.mesh = mesh
	_mesh_instance.position.y = 1.25

	var shape := CylinderShape3D.new()
	shape.radius = 0.5
	shape.height = 2.5
	_collision_shape.shape = shape
	_collision_shape.position.y = 1.25

	if _has_custom_color:
		_material.albedo_color = _custom_color
	else:
		_material.albedo_color = Color(0.5, 0.48, 0.45)
	_material.roughness = 0.8
	_mesh_instance.material_override = _material


func _setup_crystal() -> void:
	# Crystal: tall prism-like shape (use cylinder with few sides)
	var mesh := PrismMesh.new()
	mesh.size = Vector3(1.0, 2.0, 0.8)
	_mesh_instance.mesh = mesh
	_mesh_instance.position.y = 1.0

	var shape := BoxShape3D.new()
	shape.size = Vector3(0.8, 2.0, 0.6)
	_collision_shape.shape = shape
	_collision_shape.position.y = 1.0

	if _has_custom_color:
		_material.albedo_color = _custom_color
	else:
		_material.albedo_color = Color(0.6, 0.7, 0.9)
	_material.roughness = 0.2
	_material.metallic = 0.3
	_mesh_instance.material_override = _material
