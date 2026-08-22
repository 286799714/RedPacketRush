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
var _acquired_card_ids: Array[String] = []
var _final_groups: Array = []
var _activated := false
var _private_action_id := -1
var _public_action_snapshot_fresh := false
var _private_action_snapshot_fresh := false
var _pending_added_card_ids: Array[String] = []
var _pending_acquisition_context: Dictionary = {}
var _known_acquisition_event_keys: Dictionary = {}
var _has_hand_baseline := false
var _has_public_event_baseline := false


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


func get_acquired_card_ids() -> Array[String]:
	return _acquired_card_ids.duplicate()


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
	var next_room_id := str(snapshot.get("room_id", ""))
	var next_local_participant_id := str(snapshot.get("local_participant_id", ""))
	if (
		(not room_id.is_empty() and next_room_id != room_id)
		or (
			not local_participant_id.is_empty()
			and next_local_participant_id != local_participant_id
		)
	):
		_reset_acquisition_tracking()
	room_id = next_room_id
	local_participant_id = next_local_participant_id
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

	_observe_public_acquisition_events()
	_try_resolve_acquisition_highlight()

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

	var next_hand: Array[Dictionary] = []
	for raw_card: Variant in raw_hand:
		if raw_card is Dictionary:
			next_hand.append(raw_card.duplicate(true))
	var next_hand_ids := _card_id_set(next_hand)
	if not _has_hand_baseline:
		_has_hand_baseline = true
		_pending_added_card_ids.clear()
		_acquired_card_ids.clear()
	else:
		var previous_hand_ids := _card_id_set(_local_hand)
		var newly_added_card_ids: Array[String] = []
		for card in next_hand:
			var card_id := str(card.get("id", ""))
			if not card_id.is_empty() and not previous_hand_ids.has(card_id):
				newly_added_card_ids.append(card_id)
		if not newly_added_card_ids.is_empty():
			_pending_added_card_ids = newly_added_card_ids
	_local_hand = next_hand
	_acquired_card_ids = _filter_card_ids_in_hand(_acquired_card_ids, next_hand_ids)
	_pending_added_card_ids = _filter_card_ids_in_hand(
		_pending_added_card_ids,
		next_hand_ids
	)
	claim_committed = bool(snapshot.get("claim_committed", false))
	claim_card_id = snapshot.get("claim_card_id", null)
	final_committed = bool(snapshot.get("final_committed", false))
	_private_action_id = int(snapshot.get("action_id", -1))
	_private_action_snapshot_fresh = snapshot.has("action_id")
	_final_groups.clear()
	var raw_final_groups: Variant = snapshot.get("final_groups", [])
	if raw_final_groups is Array:
		_final_groups = raw_final_groups.duplicate(true)
	_try_resolve_acquisition_highlight()
	private_state_changed.emit()


func _observe_public_acquisition_events() -> void:
	var local_seat_index := _local_seat_index()
	if local_seat_index < 0:
		return
	var newest_context: Dictionary = {}
	for event in _play_events:
		if int(event.get("actor_seat_index", -1)) != local_seat_index:
			continue
		var event_key := _play_acquisition_event_key(event)
		if event_key.is_empty() or _known_acquisition_event_keys.has(event_key):
			continue
		_known_acquisition_event_keys[event_key] = true
		var candidate := {
			"type": "draw",
			"turn_number": int(event.get("turn_number", 0)),
			"event_key": event_key,
		}
		if _is_newer_acquisition_context(candidate, newest_context):
			newest_context = candidate
	for event in _claim_events:
		var turn := int(event.get("turn_number", 0))
		var raw_awards: Variant = event.get("awards", [])
		if not raw_awards is Array:
			continue
		for raw_award: Variant in raw_awards:
			if (
				not raw_award is Dictionary
				or int(raw_award.get("seat_index", -1)) != local_seat_index
			):
				continue
			var raw_card: Variant = raw_award.get("card", {})
			if not raw_card is Dictionary:
				continue
			var card_id := str(raw_card.get("id", ""))
			if card_id.is_empty():
				continue
			var event_key := "award:%d:%d:%s" % [turn, local_seat_index, card_id]
			if _known_acquisition_event_keys.has(event_key):
				continue
			_known_acquisition_event_keys[event_key] = true
			var candidate := {
				"type": "award",
				"turn_number": turn,
				"card_id": card_id,
				"event_key": event_key,
			}
			if _is_newer_acquisition_context(candidate, newest_context):
				newest_context = candidate

	if not _has_public_event_baseline:
		_has_public_event_baseline = true
		return
	if not newest_context.is_empty():
		_pending_acquisition_context = newest_context


func _try_resolve_acquisition_highlight() -> void:
	if _pending_acquisition_context.is_empty() or _pending_added_card_ids.is_empty():
		return
	var context_type := str(_pending_acquisition_context.get("type", ""))
	if context_type == "award":
		var awarded_card_id := str(_pending_acquisition_context.get("card_id", ""))
		if not _pending_added_card_ids.has(awarded_card_id):
			return
		_acquired_card_ids.clear()
		_acquired_card_ids.append(awarded_card_id)
	elif context_type == "draw":
		if _pending_added_card_ids.size() != 3:
			return
		_acquired_card_ids = _pending_added_card_ids.duplicate()
	else:
		return
	_pending_added_card_ids.clear()
	_pending_acquisition_context.clear()


func _play_acquisition_event_key(event: Dictionary) -> String:
	var raw_cards: Variant = event.get("cards", [])
	if not raw_cards is Array:
		return ""
	var played_card_ids: Array[String] = []
	for raw_card: Variant in raw_cards:
		if raw_card is Dictionary:
			var card_id := str(raw_card.get("id", ""))
			if not card_id.is_empty():
				played_card_ids.append(card_id)
	played_card_ids.sort()
	return "draw:%d:%d:%s" % [
		int(event.get("turn_number", 0)),
		int(event.get("actor_seat_index", -1)),
		",".join(played_card_ids),
	]


func _is_newer_acquisition_context(candidate: Dictionary, current: Dictionary) -> bool:
	if current.is_empty():
		return true
	var candidate_turn := int(candidate.get("turn_number", 0))
	var current_turn := int(current.get("turn_number", 0))
	if candidate_turn != current_turn:
		return candidate_turn > current_turn
	return (
		str(candidate.get("type", "")) == "award"
		and str(current.get("type", "")) != "award"
	)


func _local_seat_index() -> int:
	for participant in _participants:
		if str(participant.get("participant_id", "")) == local_participant_id:
			return int(participant.get("seat_index", -1))
	return -1


func _card_id_set(cards: Array[Dictionary]) -> Dictionary:
	var result := {}
	for card in cards:
		var card_id := str(card.get("id", ""))
		if not card_id.is_empty():
			result[card_id] = true
	return result


func _filter_card_ids_in_hand(card_ids: Array[String], hand_ids: Dictionary) -> Array[String]:
	var result: Array[String] = []
	for card_id in card_ids:
		if hand_ids.has(card_id):
			result.append(card_id)
	return result


func _reset_acquisition_tracking() -> void:
	_acquired_card_ids.clear()
	_pending_added_card_ids.clear()
	_pending_acquisition_context.clear()
	_known_acquisition_event_keys.clear()
	_has_hand_baseline = false
	_has_public_event_baseline = false


func _on_room_action_failed(code: String, message: String) -> void:
	action_failed.emit(code, message)


func _on_game_room_connection_changed(state: String, detail: String) -> void:
	connection_state = state
	if state != "connected":
		_public_action_snapshot_fresh = false
		_private_action_snapshot_fresh = false
		_reset_acquisition_tracking()
	connection_changed.emit(state, detail)


func _on_game_room_joined(_joined_room_id: String) -> void:
	# A successful join starts a new transport generation. Old room snapshots
	# must never authorize an action in the replacement room.
	action_id = -1
	action_deadline_at_unix_ms = 0.0
	_private_action_id = -1
	_public_action_snapshot_fresh = false
	_private_action_snapshot_fresh = false
	_reset_acquisition_tracking()
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
	_reset_acquisition_tracking()
	_final_groups.clear()
	_activated = false
	state_changed.emit()
	private_state_changed.emit()
	left.emit(code, reason)
