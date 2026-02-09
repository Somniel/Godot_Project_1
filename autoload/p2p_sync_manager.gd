extends Node
## Thin wrapper around Steam P2P for town-to-town CRDT field state exchange.
## Uses Steam.sendP2PPacket() / Steam.readP2PPacket() for communication
## between towns without sharing a lobby. Steam handles NAT traversal.

signal crdt_state_received(sender_steam_id: int, generation_seed: int, state: Dictionary)
signal crdt_request_received(sender_steam_id: int, generation_seed: int)

## Dedicated P2P channel for field state sync (avoid collisions with game traffic)
const CHANNEL_FIELD_SYNC: int = 2

## Message types
const MSG_CRDT_STATE: String = "crdt_state"
const MSG_CRDT_REQUEST: String = "crdt_request"

## Maximum P2P message size (Steam limit is ~1MB, but keep reasonable)
const MAX_MESSAGE_SIZE: int = 524288  # 512 KB


func _process(_delta: float) -> void:
	if not SteamManager.is_steam_initialized:
		return
	_poll_p2p_messages()


## Send CRDT state to a specific Steam user via P2P.
func send_crdt_state(target_steam_id: int, generation_seed: int, state: Dictionary) -> bool:
	var steam: Object = SteamManager.get_steam()
	if steam == null:
		return false

	var message: Dictionary = {
		"type": MSG_CRDT_STATE,
		"seed": generation_seed,
		"sender": SteamManager.get_steam_id(),
		"state": state
	}

	var json: String = JSON.stringify(message)
	var data: PackedByteArray = json.to_utf8_buffer()

	if data.size() > MAX_MESSAGE_SIZE:
		push_warning(
			(
				"P2PSyncManager: Message too large (%d bytes) for seed %d"
				% [data.size(), generation_seed]
			)
		)
		return false

	# k_EP2PSendReliable = 2
	@warning_ignore("unsafe_method_access")
	var success: bool = steam.sendP2PPacket(target_steam_id, data, 2, CHANNEL_FIELD_SYNC)

	if success:
		print(
			"P2PSyncManager: Sent CRDT state to %d for seed %d" % [target_steam_id, generation_seed]
		)
	else:
		push_warning("P2PSyncManager: Failed to send P2P to %d" % target_steam_id)
	return success


## Request CRDT state from a specific Steam user.
func request_crdt_state(target_steam_id: int, generation_seed: int) -> bool:
	var steam: Object = SteamManager.get_steam()
	if steam == null:
		return false

	var message: Dictionary = {
		"type": MSG_CRDT_REQUEST, "seed": generation_seed, "sender": SteamManager.get_steam_id()
	}

	var json: String = JSON.stringify(message)
	var data: PackedByteArray = json.to_utf8_buffer()

	# k_EP2PSendReliable = 2
	@warning_ignore("unsafe_method_access")
	var success: bool = steam.sendP2PPacket(target_steam_id, data, 2, CHANNEL_FIELD_SYNC)

	if success:
		print(
			(
				"P2PSyncManager: Requested CRDT state from %d for seed %d"
				% [target_steam_id, generation_seed]
			)
		)
	return success


## Poll for incoming P2P messages on the field sync channel.
func _poll_p2p_messages() -> void:
	var steam: Object = SteamManager.get_steam()
	if steam == null:
		return

	# Check if there are any packets available on our channel
	@warning_ignore("unsafe_method_access")
	var available: int = steam.getAvailableP2PPacketSize(CHANNEL_FIELD_SYNC)
	while available > 0:
		@warning_ignore("unsafe_method_access")
		var packet: Dictionary = steam.readP2PPacket(available, CHANNEL_FIELD_SYNC)

		if packet.is_empty():
			break

		var data: Variant = packet.get("data", PackedByteArray())
		var sender: int = packet.get("steam_id_remote", 0)

		if data is PackedByteArray:
			@warning_ignore("unsafe_cast")
			_handle_p2p_packet(sender, data as PackedByteArray)

		@warning_ignore("unsafe_method_access")
		available = steam.getAvailableP2PPacketSize(CHANNEL_FIELD_SYNC)


func _handle_p2p_packet(sender_steam_id: int, data: PackedByteArray) -> void:
	if data.is_empty():
		return

	var json_str: String = data.get_string_from_utf8()
	var parsed: Variant = JSON.parse_string(json_str)

	if not parsed is Dictionary:
		push_warning("P2PSyncManager: Invalid P2P message from %d" % sender_steam_id)
		return

	@warning_ignore("unsafe_cast")
	var message: Dictionary = parsed as Dictionary
	var msg_type: String = message.get("type", "")
	var generation_seed: int = message.get("seed", 0)

	match msg_type:
		MSG_CRDT_STATE:
			var state: Variant = message.get("state", {})
			if state is Dictionary:
				@warning_ignore("unsafe_cast")
				crdt_state_received.emit(sender_steam_id, generation_seed, state as Dictionary)
				print(
					(
						("P2PSyncManager: Received CRDT state from %d " + "for seed %d")
						% [sender_steam_id, generation_seed]
					)
				)
		MSG_CRDT_REQUEST:
			crdt_request_received.emit(sender_steam_id, generation_seed)
			print(
				(
					("P2PSyncManager: Received CRDT request from %d " + "for seed %d")
					% [sender_steam_id, generation_seed]
				)
			)
		_:
			push_warning(
				"P2PSyncManager: Unknown message type '%s' from %d" % [msg_type, sender_steam_id]
			)
