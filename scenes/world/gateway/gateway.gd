class_name Gateway
extends StaticBody3D
## Gateway for traveling between maps. Can link to field lobbies.
## Town gateways can only be configured by the host.
## Field gateways can be configured by any player.

## Emitted when a player uses this gateway to travel to an existing field
signal travel_requested(player: Node3D, destination_lobby_id: int)

## Emitted when a player travels and the field needs to be created first
signal travel_create_requested(player: Node3D, generation_seed: int, field_name: String, pearl_type: StringName)

## Emitted when a player wants to configure this gateway
signal configure_requested(player: Node3D)

## Gateway position identifier (0=North, 1=East, 2=South, 3=West)
@export var gateway_id: int = 0

## The lobby ID this gateway links to (0 = no link, or field not yet created)
@export var linked_lobby_id: int = 0

## Display name of the linked destination
@export var linked_map_name: String = ""

## Seed for generating the linked field (0 = not configured)
@export var generation_seed: int = 0

## Whether this is the origin gateway (leads back to where player came from)
@export var is_origin_gateway: bool = false

## The pearl type used to create this field (empty if not set)
@export var pearl_type: StringName = &""

@onready var _interactable: Interactable = $Interactable
@onready var _mesh: MeshInstance3D = $MeshInstance3D
@onready var _particles: GPUParticles3D = $GPUParticles3D

var _is_active: bool = false


func _ready() -> void:
	# Connect interactable signal
	if _interactable != null:
		@warning_ignore("return_value_discarded")
		_interactable.interacted.connect(_on_interacted)

	_update_visual_state()
	_update_prompt_text()


## Configure the gateway for a new field (no lobby created yet)
func set_config(field_seed: int, map_name: String, p_pearl_type: StringName = &"") -> void:
	generation_seed = field_seed
	linked_map_name = map_name
	linked_lobby_id = 0  # No lobby yet
	pearl_type = p_pearl_type
	_is_active = field_seed > 0
	_update_visual_state()
	_update_prompt_text()


## Set the gateway link to an existing destination
func set_link(lobby_id: int, map_name: String) -> void:
	linked_lobby_id = lobby_id
	linked_map_name = map_name
	# Keep the seed for reference but lobby_id takes precedence
	_is_active = lobby_id > 0 or generation_seed > 0
	_update_visual_state()
	_update_prompt_text()


## Update the lobby ID after field creation (keeps existing config)
func set_lobby_id(lobby_id: int) -> void:
	linked_lobby_id = lobby_id
	_update_visual_state()


## Clear the gateway link
func clear_link() -> void:
	linked_lobby_id = 0
	linked_map_name = ""
	generation_seed = 0
	pearl_type = &""
	_is_active = false
	_update_visual_state()
	_update_prompt_text()


## Check if this gateway is configured (has seed or lobby)
func has_link() -> bool:
	return linked_lobby_id > 0 or generation_seed > 0


## Check if the field needs to be created (configured but no lobby yet)
func needs_field_creation() -> bool:
	return linked_lobby_id == 0 and generation_seed > 0


## Get the direction name for this gateway
func get_direction_name() -> String:
	match gateway_id:
		0: return "North"
		1: return "East"
		2: return "South"
		3: return "West"
		_: return "Gateway"


func _update_visual_state() -> void:
	# Show particles when gateway is active
	if _particles != null:
		_particles.emitting = _is_active

	# Change mesh color based on state
	if _mesh != null:
		var mat: StandardMaterial3D = _mesh.get_surface_override_material(0)
		if mat == null:
			mat = StandardMaterial3D.new()
			_mesh.set_surface_override_material(0, mat)
		if _is_active:
			mat.albedo_color = Color(0.3, 0.5, 0.8, 1.0)  # Blue when active
			mat.emission_enabled = true
			mat.emission = Color(0.2, 0.3, 0.5, 1.0)
			mat.emission_energy_multiplier = 0.5
		else:
			mat.albedo_color = Color(0.4, 0.4, 0.4, 1.0)  # Gray when inactive
			mat.emission_enabled = false


func _update_prompt_text() -> void:
	if _interactable == null:
		return

	if has_link():
		_interactable.interaction_type = "Travel to"
		if is_origin_gateway:
			_interactable.object_name = "Return (%s)" % linked_map_name
		else:
			_interactable.object_name = linked_map_name
	else:
		_interactable.interaction_type = "Configure"
		_interactable.object_name = "%s Gateway" % get_direction_name()


func _on_interacted(player: Node3D) -> void:
	if has_link():
		if needs_field_creation():
			# Field configured but not created yet - create and travel
			travel_create_requested.emit(player, generation_seed, linked_map_name, pearl_type)
		else:
			# Travel to existing destination
			travel_requested.emit(player, linked_lobby_id)
	else:
		# Open configuration UI
		configure_requested.emit(player)
