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
var turn_number := 0
var played_category := ""
var played_score := 0
var claim_commit_count := 0
var claim_committed := false
var claim_card_id: Variant = null

var _adapter: Object
var _participants: Array[Dictionary] = []
var _contest_rounds: Array[Dictionary] = []
var _played_cards: Array[Dictionary] = []
var _play_events: Array[Dictionary] = []
var _claim_events: Array[Dictionary] = []
var _revealed_claims: Array[Dictionary] = []
var _claim_awards: Array[Dictionary] = []
var _discarded_cards: Array[Dictionary] = []
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


func get_played_cards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card in _played_cards:
		result.append(card.duplicate(true))
	return result


func get_play_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for play_event in _play_events:
		result.append(play_event.duplicate(true))
	return result


func get_claim_events() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for claim_event in _claim_events:
		result.append(claim_event.duplicate(true))
	return result


func get_revealed_claims() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for claim in _revealed_claims:
		result.append(claim.duplicate(true))
	return result


func get_claim_awards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for award in _claim_awards:
		result.append(award.duplicate(true))
	return result


func get_discarded_cards() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card in _discarded_cards:
		result.append(card.duplicate(true))
	return result


func get_local_hand() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for card in _local_hand:
		result.append(card.duplicate(true))
	return result


func play_cards(card_ids: Array[String]) -> void:
	_adapter.play_cards(card_ids.duplicate())


func claim_card(card_id: Variant) -> void:
	_adapter.claim_card(card_id)


func _on_game_room_state_changed(snapshot: Dictionary) -> void:
	room_id = str(snapshot.get("room_id", ""))
	local_participant_id = str(snapshot.get("local_participant_id", ""))
	status = str(snapshot.get("status", ""))
	phase = str(snapshot.get("phase", ""))
	actor_seat_index = int(snapshot.get("actor_seat_index", -1))
	draw_pile_count = int(snapshot.get("draw_pile_count", 0))
	turn_number = int(snapshot.get("turn_number", 0))
	played_category = str(snapshot.get("played_category", ""))
	played_score = int(snapshot.get("played_score", 0))
	claim_commit_count = clampi(int(snapshot.get("claim_commit_count", 0)), 0, 3)

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

	_revealed_claims.clear()
	var raw_revealed_claims: Variant = snapshot.get("revealed_claims", [])
	if raw_revealed_claims is Array:
		for raw_claim: Variant in raw_revealed_claims:
			if raw_claim is Dictionary:
				_revealed_claims.append(raw_claim.duplicate(true))

	_claim_awards.clear()
	var raw_claim_awards: Variant = snapshot.get("claim_awards", [])
	if raw_claim_awards is Array:
		for raw_award: Variant in raw_claim_awards:
			if raw_award is Dictionary:
				_claim_awards.append(raw_award.duplicate(true))

	_discarded_cards.clear()
	var raw_discarded_cards: Variant = snapshot.get("discarded_cards", [])
	if raw_discarded_cards is Array:
		for raw_card: Variant in raw_discarded_cards:
			if raw_card is Dictionary:
				_discarded_cards.append(raw_card.duplicate(true))

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
	turn_number = 0
	played_category = ""
	played_score = 0
	claim_commit_count = 0
	claim_committed = false
	claim_card_id = null
	_participants.clear()
	_contest_rounds.clear()
	_played_cards.clear()
	_play_events.clear()
	_claim_events.clear()
	_revealed_claims.clear()
	_claim_awards.clear()
	_discarded_cards.clear()
	_local_hand.clear()
	_activated = false
	state_changed.emit()
	private_state_changed.emit()
	left.emit(code, reason)
