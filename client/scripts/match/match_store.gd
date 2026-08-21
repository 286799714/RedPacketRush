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
var deck_mode := "one"
var phase := ""
var action_id := -1
var action_deadline_at_unix_ms := 0.0
var actor_seat_index := -1
var draw_pile_count := 0
var sealed_card_count := 0
var turn_number := 0
var played_category := ""
var played_score := 0
var claim_committed := false
var claim_card_id: Variant = null
var final_committed := false
var connection_state := "disconnected"

var _adapter: Object
var _participants: Array[Dictionary] = []
var _contest_rounds: Array[Dictionary] = []
var _played_cards: Array[Dictionary] = []
var _play_events: Array[Dictionary] = []
var _claim_events: Array[Dictionary] = []
var _discard_events: Array[Dictionary] = []
var _pending_discard_seat_indexes: Array[int] = []
var _final_results: Array[Dictionary] = []
var _winner_seat_indexes: Array[int] = []
var _final_events: Array[Dictionary] = []
var _local_hand: Array[Dictionary] = []
var _final_groups: Array = []
var _activated := false
var _private_action_id := -1
var _public_action_snapshot_fresh := false
var _private_action_snapshot_fresh := false


func _init(adapter: Object) -> void:
	_adapter = adapter
	_adapter.game_room_state_changed.connect(_on_game_room_state_changed)
	if _adapter.has_signal("match_private_state_changed"):
		_adapter.match_private_state_changed.connect(_on_match_private_state_changed)
	_adapter.room_action_failed.connect(_on_room_action_failed)
	_adapter.game_room_left.connect(_on_game_room_left)
	if _adapter.has_signal("game_room_connection_changed"):
		_adapter.game_room_connection_changed.connect(_on_game_room_connection_changed)
	if _adapter.has_signal("game_room_joined"):
		_adapter.game_room_joined.connect(_on_game_room_joined)


func get_participants() -> Array[Dictionary]:
	return _duplicate_dictionary_array(_participants)


func get_contest_rounds() -> Array[Dictionary]:
	return _duplicate_dictionary_array(_contest_rounds)


func get_played_cards() -> Array[Dictionary]:
	return _duplicate_dictionary_array(_played_cards)


func get_play_events() -> Array[Dictionary]:
	return _duplicate_dictionary_array(_play_events)


func get_claim_events() -> Array[Dictionary]:
	return _duplicate_dictionary_array(_claim_events)


func get_discard_events() -> Array[Dictionary]:
	return _duplicate_dictionary_array(_discard_events)


func get_pending_discard_seat_indexes() -> Array[int]:
	return _pending_discard_seat_indexes.duplicate()


func get_final_results() -> Array[Dictionary]:
	return _duplicate_dictionary_array(_final_results)


func get_winner_seat_indexes() -> Array[int]:
	return _winner_seat_indexes.duplicate()


func get_final_events() -> Array[Dictionary]:
	return _duplicate_dictionary_array(_final_events)


func get_local_hand() -> Array[Dictionary]:
	return _duplicate_dictionary_array(_local_hand)


func get_final_groups() -> Array:
	return _final_groups.duplicate(true)


func is_action_context_ready() -> bool:
	return (
		connection_state == "connected"
		and _public_action_snapshot_fresh
		and _private_action_snapshot_fresh
		and action_id == _private_action_id
	)


func _duplicate_dictionary_array(source: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for item in source:
		result.append(item.duplicate(true))
	return result


func play_cards(card_ids: Array[String]) -> void:
	if not is_action_context_ready():
		return
	_adapter.play_cards(card_ids.duplicate(), action_id)


func claim_card(card_id: Variant) -> void:
	if not is_action_context_ready():
		return
	_adapter.claim_card(card_id, action_id)


func discard_card(card_id: String, expected_turn_number: int) -> void:
	if not is_action_context_ready():
		return
	_adapter.discard_card(card_id, expected_turn_number, action_id)


func submit_final_selection(groups: Array) -> void:
	if not is_action_context_ready():
		return
	_adapter.submit_final_selection(groups.duplicate(true), action_id)


func submit_best_final_selection() -> void:
	if not is_action_context_ready():
		return
	_adapter.submit_best_final_selection(action_id)


func _on_game_room_state_changed(snapshot: Dictionary) -> void:
	room_id = str(snapshot.get("room_id", ""))
	local_participant_id = str(snapshot.get("local_participant_id", ""))
	status = str(snapshot.get("status", ""))
	deck_mode = str(snapshot.get("deck_mode", "one"))
	phase = str(snapshot.get("phase", ""))
	action_id = int(snapshot.get("action_id", -1))
	action_deadline_at_unix_ms = float(snapshot.get("action_deadline_at_unix_ms", 0.0))
	_public_action_snapshot_fresh = snapshot.has("action_id")
	actor_seat_index = int(snapshot.get("actor_seat_index", -1))
	draw_pile_count = int(snapshot.get("draw_pile_count", 0))
	sealed_card_count = int(snapshot.get("sealed_card_count", 0))
	turn_number = int(snapshot.get("turn_number", 0))
	played_category = str(snapshot.get("played_category", ""))
	played_score = int(snapshot.get("played_score", 0))

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
					"is_connected": bool(raw_seat.get("is_connected", false)),
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

	_played_cards.clear()
	var raw_played_cards: Variant = snapshot.get("played_cards", [])
	if raw_played_cards is Array:
		for raw_card: Variant in raw_played_cards:
			if raw_card is Dictionary:
				_played_cards.append(raw_card.duplicate(true))

	_play_events.clear()
	var raw_play_events: Variant = snapshot.get("play_events", [])
	if raw_play_events is Array:
		for raw_event: Variant in raw_play_events:
			if raw_event is Dictionary:
				_play_events.append(raw_event.duplicate(true))

	_claim_events.clear()
	var raw_claim_events: Variant = snapshot.get("claim_events", [])
	if raw_claim_events is Array:
		for raw_event: Variant in raw_claim_events:
			if raw_event is Dictionary:
				_claim_events.append(raw_event.duplicate(true))

	_discard_events.clear()
	var raw_discard_events: Variant = snapshot.get("discard_events", [])
	if raw_discard_events is Array:
		for raw_event: Variant in raw_discard_events:
			if raw_event is Dictionary:
				_discard_events.append(raw_event.duplicate(true))

	_pending_discard_seat_indexes.clear()
	var raw_pending_discard_seats: Variant = snapshot.get("pending_discard_seat_indexes", [])
	if raw_pending_discard_seats is Array:
		for raw_seat_index: Variant in raw_pending_discard_seats:
			_pending_discard_seat_indexes.append(int(raw_seat_index))

	_final_results.clear()
	var raw_final_results: Variant = snapshot.get("final_results", [])
	if raw_final_results is Array:
		for raw_result: Variant in raw_final_results:
			if raw_result is Dictionary:
				_final_results.append(raw_result.duplicate(true))

	_winner_seat_indexes.clear()
	var raw_winner_seat_indexes: Variant = snapshot.get("winner_seat_indexes", [])
	if raw_winner_seat_indexes is Array:
		for raw_seat_index: Variant in raw_winner_seat_indexes:
			_winner_seat_indexes.append(int(raw_seat_index))

	_final_events.clear()
	var raw_final_events: Variant = snapshot.get("final_events", [])
	if raw_final_events is Array:
		for raw_event: Variant in raw_final_events:
			if raw_event is Dictionary:
				_final_events.append(raw_event.duplicate(true))

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
	claim_committed = bool(snapshot.get("claim_committed", false))
	claim_card_id = snapshot.get("claim_card_id", null)
	final_committed = bool(snapshot.get("final_committed", false))
	_private_action_id = int(snapshot.get("action_id", -1))
	_private_action_snapshot_fresh = snapshot.has("action_id")
	_final_groups.clear()
	var raw_final_groups: Variant = snapshot.get("final_groups", [])
	if raw_final_groups is Array:
		_final_groups = raw_final_groups.duplicate(true)
	private_state_changed.emit()


func _on_room_action_failed(code: String, message: String) -> void:
	action_failed.emit(code, message)


func _on_game_room_connection_changed(state: String, detail: String) -> void:
	connection_state = state
	if state != "connected":
		_public_action_snapshot_fresh = false
		_private_action_snapshot_fresh = false
	connection_changed.emit(state, detail)


func _on_game_room_joined(_joined_room_id: String) -> void:
	# A successful join starts a new transport generation. Old room snapshots
	# must never authorize an action in the replacement room.
	action_id = -1
	action_deadline_at_unix_ms = 0.0
	_private_action_id = -1
	_public_action_snapshot_fresh = false
	_private_action_snapshot_fresh = false
	state_changed.emit()


func _on_game_room_left(code: int, reason: String) -> void:
	room_id = ""
	local_participant_id = ""
	status = ""
	deck_mode = "one"
	phase = ""
	action_id = -1
	action_deadline_at_unix_ms = 0.0
	actor_seat_index = -1
	draw_pile_count = 0
	sealed_card_count = 0
	turn_number = 0
	played_category = ""
	played_score = 0
	claim_committed = false
	claim_card_id = null
	final_committed = false
	connection_state = "disconnected"
	_private_action_id = -1
	_public_action_snapshot_fresh = false
	_private_action_snapshot_fresh = false
	_participants.clear()
	_contest_rounds.clear()
	_played_cards.clear()
	_play_events.clear()
	_claim_events.clear()
	_discard_events.clear()
	_pending_discard_seat_indexes.clear()
	_final_results.clear()
	_winner_seat_indexes.clear()
	_final_events.clear()
	_local_hand.clear()
	_final_groups.clear()
	_activated = false
	state_changed.emit()
	private_state_changed.emit()
	left.emit(code, reason)
