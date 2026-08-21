extends RefCounted

signal connection_state_changed(state: String, detail: String)
signal lobby_rooms_changed(rooms: Array[Dictionary])
signal game_room_joined(room_id: String)
signal game_room_failed(message: String)
signal game_room_state_changed(state: Dictionary)
signal match_private_state_changed(state: Dictionary)
signal room_action_failed(code: String, message: String)
signal game_room_left(code: int, reason: String)
signal game_room_connection_changed(state: String, detail: String)

var connection_requests: Array[Dictionary] = []
var room_requests: Array[Dictionary] = []
var leave_game_room_requests := 0


func connect_lobby(endpoint: String, nickname: String) -> void:
	connection_requests.append({"endpoint": endpoint, "nickname": nickname})


func publish_connection_state(state: String, detail: String = "") -> void:
	connection_state_changed.emit(state, detail)


func publish_rooms(rooms: Array[Dictionary]) -> void:
	lobby_rooms_changed.emit(rooms)


func publish_game_room_state(state: Dictionary) -> void:
	game_room_state_changed.emit(state)


func publish_match_private_state(state: Dictionary) -> void:
	match_private_state_changed.emit(state)


func publish_game_room_joined(room_id: String) -> void:
	game_room_joined.emit(room_id)


func publish_room_error(code: String, message: String) -> void:
	room_action_failed.emit(code, message)


func publish_game_room_left(code: int = 1000, reason: String = "") -> void:
	game_room_left.emit(code, reason)


func publish_game_room_connection_state(state: String, detail: String = "") -> void:
	game_room_connection_changed.emit(state, detail)


func set_ready(ready: bool) -> void:
	room_requests.append({"type": "set_ready", "payload": {"ready": ready}})


func configure_room(configuration: Object) -> void:
	room_requests.append({
		"type": "configure",
		"payload": {
			"deckMode": configuration.deck_mode,
			"actionDeadlineSeconds": configuration.action_deadline_seconds,
		},
	})


func fill_bots() -> void:
	room_requests.append({"type": "fill_bots", "payload": null})


func start_match() -> void:
	room_requests.append({"type": "start", "payload": null})


func play_cards(card_ids: Array[String]) -> void:
	room_requests.append({
		"type": "play_cards",
		"payload": {"cardIds": card_ids.duplicate()},
	})


func claim_card(card_id: Variant) -> void:
	room_requests.append({
		"type": "claim",
		"payload": {"cardId": card_id},
	})


func discard_card(card_id: String, turn_number: int) -> void:
	room_requests.append({
		"type": "discard",
		"payload": {"cardId": card_id, "turnNumber": turn_number},
	})


func submit_final_selection(groups: Array) -> void:
	room_requests.append({
		"type": "final_selection",
		"payload": {"mode": "manual", "groups": groups.duplicate(true)},
	})


func submit_best_final_selection() -> void:
	room_requests.append({
		"type": "final_selection",
		"payload": {"mode": "best"},
	})


func leave_game_room() -> void:
	leave_game_room_requests += 1
