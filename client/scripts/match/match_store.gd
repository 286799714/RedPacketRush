extends RefCounted
class_name MatchStore

signal match_activated()
signal state_changed()
signal private_state_changed()
signal action_failed(code: String, message: String)
signal left(code: int, reason: String)
signal connection_changed(state: String, detail: String)

var room_id := ""
var local_participant_id := ""
var status := ""
var phase := ""
var actor_seat_index := -1
var draw_pile_count := 0

var _adapter: Object
var _participants: Array[Dictionary] = []
var _contest_rounds: Array[Dictionary] = []
var _local_hand: Array[Dictionary] = []
var _activated := false


func _init(adapter: Object) -> void:
	_adapter = adapter
	_adapter.game_room_state_changed.connect(_on_game_room_state_changed)
	if _adapter.has_signal("match_private_state_changed"):
		_adapter.match_private_state_changed.connect(_on_match_private_state_changed)
	_adapter.room_action_failed.connect(_on_room_action_failed)
	_adapter.game_room_left.connect(_on_game_room_left)
	if _adapter.has_signal("game_room_connection_changed"):
		_adapter.game_room_connection_changed.connect(_on_game_room_connection_changed)


func get_participants() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for participant in _participants:
		result.append(participant.duplicate(true))
	return result


func get_contest_rounds() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for contest_round in _contest_rounds:
		result.append(contest_round.duplicate(true))
	return result


func get_local_hand() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card in _local_hand:
		result.append(card.duplicate(true))
	return result


func _on_game_room_state_changed(snapshot: Dictionary) -> void:
	room_id = str(snapshot.get("room_id", ""))
	local_participant_id = str(snapshot.get("local_participant_id", ""))
	status = str(snapshot.get("status", ""))
	phase = str(snapshot.get("phase", ""))
	actor_seat_index = int(snapshot.get("actor_seat_index", -1))
	draw_pile_count = int(snapshot.get("draw_pile_count", 0))

	_participants.clear()
	var raw_seats: Variant = snapshot.get("seats", [])
	if raw_seats is Array:
		for raw_seat: Variant in raw_seats:
			if raw_seat is Dictionary:
				_participants.append({
					"seat_index": int(raw_seat.get("seat_index", -1)),
					"participant_id": str(raw_seat.get("participant_id", "")),
					"nickname": str(raw_seat.get("nickname", "")),
					"is_bot": bool(raw_seat.get("is_bot", false)),
					"is_ready": bool(raw_seat.get("is_ready", false)),
					"score": int(raw_seat.get("score", 0)),
					"hand_count": int(raw_seat.get("hand_count", 0)),
				})

	_contest_rounds.clear()
	var raw_rounds: Variant = snapshot.get("contest_rounds", [])
	if raw_rounds is Array:
		for raw_round: Variant in raw_rounds:
			if raw_round is Dictionary:
				_contest_rounds.append(raw_round.duplicate(true))

	state_changed.emit()
	if status == "started" and not _activated:
		_activated = true
		match_activated.emit()


func _on_match_private_state_changed(snapshot: Dictionary) -> void:
	if local_participant_id.is_empty():
		return
	if str(snapshot.get("participant_id", "")) != local_participant_id:
		return
	var raw_hand: Variant = snapshot.get("hand", null)
	if not raw_hand is Array:
		return

	_local_hand.clear()
	for raw_card: Variant in raw_hand:
		if raw_card is Dictionary:
			_local_hand.append(raw_card.duplicate(true))
	private_state_changed.emit()


func _on_room_action_failed(code: String, message: String) -> void:
	action_failed.emit(code, message)


func _on_game_room_connection_changed(state: String, detail: String) -> void:
	connection_changed.emit(state, detail)


func _on_game_room_left(code: int, reason: String) -> void:
	room_id = ""
	local_participant_id = ""
	status = ""
	phase = ""
	actor_seat_index = -1
	draw_pile_count = 0
	_participants.clear()
	_contest_rounds.clear()
	_local_hand.clear()
	_activated = false
	state_changed.emit()
	private_state_changed.emit()
	left.emit(code, reason)
