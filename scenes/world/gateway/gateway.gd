class_name Gateway
extends StaticBody3D
## Gateway for traveling between maps. Can link to fields or towns.
## Town gateways can only link to fields.
## Field gateways can link to towns (return) or other fields.

## Link type distinguishes destination types for travel logic
enum LinkType { NONE, FIELD, TOWN }

## Emitted when a player uses this gateway to travel to an existing destination
signal travel_requested(player: Node3D, destination_lobby_id: int)

## Emitted when a player travels and the field needs to be created first
signal travel_create_requested(
	player: Node3D, generation_seed: int, field_name: String, pearl_type: StringName
)

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

## The specific gateway ID to arrive at in the destination (-1 = use default logic)
## Used when linking to a specific town gateway via the "Link to Town" feature.
@export var linked_gateway_id: int = -1

## The type of link: NONE, FIELD, or TOWN
## Town gateways only use FIELD. Field gateways use TOWN (return) or FIELD (chain).
@export var link_type: int = LinkType.NONE

## Steam ID of the town owner (only used when link_type == TOWN)
## This is the stable identifier for town destinations.
@export var linked_owner_steam_id: int = 0

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
	link_type = LinkType.FIELD
	generation_seed = field_seed
	linked_map_name = map_name
	linked_lobby_id = 0  # No lobby yet
	pearl_type = p_pearl_type
	linked_owner_steam_id = 0  # Field links don't use owner ID
	_is_active = field_seed > 0
	_update_visual_state()
	_update_prompt_text()


## Set the gateway link to an existing field destination
func set_link(lobby_id: int, map_name: String, target_gateway_id: int = -1) -> void:
	link_type = LinkType.FIELD
	linked_lobby_id = lobby_id
	linked_map_name = map_name
	linked_gateway_id = target_gateway_id
	linked_owner_steam_id = 0  # Field links don't use owner ID
	# Keep the seed for reference but lobby_id takes precedence
	_is_active = lobby_id > 0 or generation_seed > 0
	_update_visual_state()
	_update_prompt_text()


## Set the gateway link to a player's town (only used by field gateways)
func set_town_link(
	owner_steam_id: int, lobby_id: int, map_name: String, target_gateway_id: int = -1
) -> void:
	link_type = LinkType.TOWN
	linked_owner_steam_id = owner_steam_id
	linked_lobby_id = lobby_id  # Cached, may be stale
	linked_map_name = map_name
	linked_gateway_id = target_gateway_id
	generation_seed = 0  # Town links don't have seeds
	pearl_type = &""
	_is_active = owner_steam_id > 0
	_update_visual_state()
	_update_prompt_text()


## Update the lobby ID after field creation (keeps existing config)
func set_lobby_id(lobby_id: int) -> void:
	linked_lobby_id = lobby_id
	_update_visual_state()


## Clear the gateway link
func clear_link() -> void:
	link_type = LinkType.NONE
	linked_lobby_id = 0
	linked_map_name = ""
	generation_seed = 0
	pearl_type = &""
	linked_gateway_id = -1
	linked_owner_steam_id = 0
	_is_active = false
	_update_visual_state()
	_update_prompt_text()


## Check if this gateway is configured
func has_link() -> bool:
	return link_type != LinkType.NONE


## Check if the field needs to be created (field link configured but no lobby yet)
func needs_field_creation() -> bool:
	return link_type == LinkType.FIELD and linked_lobby_id == 0 and generation_seed > 0


## Check if this is a field link
func is_field_link() -> bool:
	return link_type == LinkType.FIELD


## Check if this is a town link (return to player's town)
func is_town_link() -> bool:
	return link_type == LinkType.TOWN


## Check if the destination needs lobby lookup (town links may have stale cached lobby IDs)
func needs_lobby_lookup() -> bool:
	if link_type == LinkType.TOWN:
		# Town links always need lookup since cached lobby may be stale
		return linked_lobby_id == 0 or true  # TODO: implement lobby lookup
	return false


## Get the direction name for this gateway
func get_direction_name() -> String:
	match gateway_id:
		0:
			return "North"
		1:
			return "East"
		2:
			return "South"
		3:
			return "West"
		_:
			return "Gateway"


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
