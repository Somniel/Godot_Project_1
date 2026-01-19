extends CharacterBody3D
## Networked player controller with WASD movement and right-click camera.
## Movement is only processed by the owning peer.

const SPEED: float = 5.0
const JUMP_VELOCITY: float = 4.5
const MOUSE_SENSITIVITY: float = 0.3

var _gravity: float = ProjectSettings.get_setting("physics/3d/default_gravity")
var _camera: Camera3D = null
var _camera_pivot: Node3D = null
var _is_rotating_camera: bool = false
var _current_interactable: Interactable = null
var _nearby_interactables: Array[Interactable] = []

@onready var _name_label: Label3D = $NameLabel
@onready var _interaction_area: Area3D = $InteractionArea
@onready var _hotkey_label: Label3D = $HotkeyLabel


func _ready() -> void:
	# Defer setup to ensure multiplayer authority is set
	call_deferred("_deferred_setup")


func _deferred_setup() -> void:
	# Only the owning peer controls this player
	if is_multiplayer_authority():
		_setup_camera()
		_setup_interaction()
		# Sync our name to all other players
		_sync_player_name.rpc(SteamManager.get_steam_username())

	# Update visuals for all players
	_update_name_label()
	_update_player_color()


func _input(event: InputEvent) -> void:
	if not is_multiplayer_authority():
		return

	# Toggle inventory with Tab
	if event.is_action_pressed("toggle_inventory"):
		_toggle_inventory()
		return

	# Right mouse button for camera rotation (only when inventory is closed)
	var mouse_button := event as InputEventMouseButton
	if mouse_button and mouse_button.button_index == MOUSE_BUTTON_RIGHT:
		if not _is_inventory_open():
			_is_rotating_camera = mouse_button.pressed
			# Capture/release mouse
			if _is_rotating_camera:
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			else:
				Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

	# Mouse motion for camera rotation
	var mouse_motion := event as InputEventMouseMotion
	if mouse_motion and _is_rotating_camera and _camera_pivot:
		_camera_pivot.rotate_y(deg_to_rad(-mouse_motion.relative.x * MOUSE_SENSITIVITY))
		_camera.rotate_x(deg_to_rad(-mouse_motion.relative.y * MOUSE_SENSITIVITY))
		# Clamp vertical rotation
		_camera.rotation.x = clamp(_camera.rotation.x, deg_to_rad(-80.0), deg_to_rad(80.0))

	# Handle interact input (only when inventory is closed)
	if event.is_action_pressed("interact") and _current_interactable:
		if not _is_inventory_open():
			_current_interactable.interact(self)


func _physics_process(delta: float) -> void:
	# Only process input if we own this player
	if not is_multiplayer_authority():
		return

	# Apply gravity
	if not is_on_floor():
		velocity.y -= _gravity * delta

	# Handle jump
	if Input.is_action_just_pressed("ui_accept") and is_on_floor():
		velocity.y = JUMP_VELOCITY

	# Get WASD input
	var input_dir := Vector2.ZERO
	if Input.is_key_pressed(KEY_W):
		input_dir.y -= 1
	if Input.is_key_pressed(KEY_S):
		input_dir.y += 1
	if Input.is_key_pressed(KEY_A):
		input_dir.x -= 1
	if Input.is_key_pressed(KEY_D):
		input_dir.x += 1
	input_dir = input_dir.normalized()

	# Convert to 3D direction relative to camera pivot orientation
	var direction := Vector3.ZERO
	if _camera_pivot and input_dir != Vector2.ZERO:
		var forward := -_camera_pivot.global_transform.basis.z
		var right := _camera_pivot.global_transform.basis.x
		forward.y = 0
		right.y = 0
		forward = forward.normalized()
		right = right.normalized()
		direction = (forward * -input_dir.y + right * input_dir.x).normalized()
	elif input_dir != Vector2.ZERO:
		direction = Vector3(input_dir.x, 0, input_dir.y).normalized()

	if direction:
		velocity.x = direction.x * SPEED
		velocity.z = direction.z * SPEED
	else:
		velocity.x = move_toward(velocity.x, 0, SPEED)
		velocity.z = move_toward(velocity.z, 0, SPEED)

	@warning_ignore("return_value_discarded")
	move_and_slide()


func _setup_camera() -> void:
	# Create a pivot for horizontal rotation (yaw)
	_camera_pivot = Node3D.new()
	_camera_pivot.name = "CameraPivot"
	add_child(_camera_pivot)

	# Create camera as child of pivot for vertical rotation (pitch)
	_camera = Camera3D.new()
	_camera.name = "PlayerCamera"
	_camera.position = Vector3(0, 5, 8)
	_camera.rotation_degrees = Vector3(-25, 0, 0)
	_camera_pivot.add_child(_camera)
	_camera.make_current()


func _setup_interaction() -> void:
	# Connect interaction area signals
	@warning_ignore("return_value_discarded")
	_interaction_area.area_entered.connect(_on_interactable_entered)
	@warning_ignore("return_value_discarded")
	_interaction_area.area_exited.connect(_on_interactable_exited)


func _on_interactable_entered(area: Area3D) -> void:
	if area is Interactable:
		_nearby_interactables.append(area)
		_update_current_interactable()


func _on_interactable_exited(area: Area3D) -> void:
	if area is Interactable:
		_nearby_interactables.erase(area)
		_update_current_interactable()


func _update_current_interactable() -> void:
	var previous_interactable: Interactable = _current_interactable

	if _nearby_interactables.is_empty():
		_current_interactable = null
	else:
		# Get closest interactable
		var closest: Interactable = null
		var closest_dist: float = INF
		for interactable: Interactable in _nearby_interactables:
			var dist: float = global_position.distance_to(interactable.global_position)
			if dist < closest_dist:
				closest_dist = dist
				closest = interactable
		_current_interactable = closest

	# Update prompt visibility on interactables and player hotkey label
	if previous_interactable != _current_interactable:
		if previous_interactable:
			previous_interactable.hide_prompt()
		if _current_interactable:
			_current_interactable.show_prompt()

		# Show/hide hotkey label above player
		if _hotkey_label:
			_hotkey_label.visible = _current_interactable != null


func _update_name_label() -> void:
	if _name_label == null:
		return

	var peer_id: int = get_multiplayer_authority()

	if peer_id == multiplayer.get_unique_id():
		# Local player - use Steam name
		_name_label.text = SteamManager.get_steam_username()
	else:
		# Other player - will be updated via RPC
		_name_label.text = "Player %d" % peer_id


func _update_player_color() -> void:
	var mesh_instance: MeshInstance3D = $MeshInstance3D
	if mesh_instance == null:
		return

	var peer_id: int = get_multiplayer_authority()
	var material := StandardMaterial3D.new()

	if peer_id == 1:
		# Host is blue
		material.albedo_color = Color(0.2, 0.6, 1.0)
	else:
		# Clients are red
		material.albedo_color = Color(1.0, 0.3, 0.3)

	mesh_instance.material_override = material


@rpc("any_peer", "call_local", "reliable")
func _sync_player_name(player_name: String) -> void:
	# Validate sender - only accept name from the player's owning peer
	var sender_id: int = multiplayer.get_remote_sender_id()
	# sender_id is 0 for local calls, otherwise must match authority
	if sender_id != 0 and sender_id != get_multiplayer_authority():
		push_warning("Rejected unauthorized name sync from peer %d" % sender_id)
		return
	if _name_label:
		_name_label.text = Utils.sanitize_display_string(player_name)


func _toggle_inventory() -> void:
	## Toggle the inventory UI open/closed.
	var world: Node = get_tree().current_scene
	if world == null:
		return

	var inventory_ui: InventoryUI = world.get_node_or_null("UI/InventoryUI")
	if inventory_ui != null:
		inventory_ui.toggle_inventory()

		# Release camera rotation if opening inventory
		if inventory_ui.is_open():
			_is_rotating_camera = false
			Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _is_inventory_open() -> bool:
	## Check if inventory UI is currently open.
	var world: Node = get_tree().current_scene
	if world == null:
		return false

	var inventory_ui: InventoryUI = world.get_node_or_null("UI/InventoryUI")
	if inventory_ui != null:
		return inventory_ui.is_open()
	return false
