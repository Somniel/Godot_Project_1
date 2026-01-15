extends StaticBody3D
## Interactable totem that displays lobby information when activated.

@onready var _interactable: Interactable = $Interactable
@onready var _lobby_info_ui: LobbyInfoUI = $UILayer/LobbyInfoUI


func _ready() -> void:
	@warning_ignore("return_value_discarded")
	_interactable.interacted.connect(_on_interacted)


func _on_interacted(_player: Node3D) -> void:
	_lobby_info_ui.show_lobby_info()
