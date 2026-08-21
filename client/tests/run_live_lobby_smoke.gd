extends SceneTree

const ColyseusRealtimeAdapter = preload("res://scripts/network/colyseus_realtime_adapter.gd")
const TEST_TIMEOUT_SECONDS := 12.0
const TEST_ROOM_NAME := "Native SDK smoke room"
const PARTICIPANT_NAMES := [
	"Smoke Host",
	"Smoke Guest 2",
	"Smoke Guest 3",
	"Smoke Guest 4",
]

var _endpoint := ""
var _adapters: Array[ColyseusRealtimeAdapter] = []
var _deadline_msec := 0
var _connected_participants: Dictionary = {}
var _initial_rooms_observed := false
var _creation_requested := false
var _guests_requested := false
var _listed_room_id := ""
var _joined_room_ids: Dictionary = {}
var _room_state_observed := false
var _four_participants_observed := false
var _ready_requested: Dictionary = {}
var _readiness_observed := false
var _start_requested := false
var _point_contest_observed := false
var _opening_public_observed := false
var _participant_ids_by_adapter: Dictionary = {}
var _opening_hands_by_adapter: Dictionary = {}
var _private_message_counts: Dictionary = {}
var _private_hand_observed := false
var _actor_seat_index := -1
var _actor_participant_id := ""
var _actor_adapter_index := -1
var _actor_played_card_ids: Array[String] = []
var _actor_play_requested := false
var _claim_commit_observed := false
var _actor_replacement_observed := false
var _claim_requests: Dictionary = {}
var _claim_confirmations: Dictionary = {}
var _claim_reveals_by_adapter: Dictionary = {}
var _failure := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_endpoint = _read_endpoint()
	if _endpoint.is_empty():
		_fail("missing --endpoint=ws://host:port")
		_finish()
		return

	_deadline_msec = Time.get_ticks_msec() + int(TEST_TIMEOUT_SECONDS * 1000.0)
	_create_participant_adapter(0)

	while _failure.is_empty() and not _is_complete() and Time.get_ticks_msec() < _deadline_msec:
		await process_frame

	if _failure.is_empty() and not _is_complete():
		_fail(
			(
				"timed out waiting for native actor-play flow "
				+ "(connected=%d, initial=%s, listed=%s, joined=%d, state=%s, "
				+ "four_participants=%s, ready=%s, point_contest=%s, opening=%s, "
				+ "private_hands=%d, actor=%d, play=%s, claim_commit=%s, replacement=%s, "
				+ "claim_requests=%d, confirmations=%d, reveals=%d)"
			)
			% [
				_connected_participants.size(),
				_initial_rooms_observed,
				_listed_room_id,
				_joined_room_ids.size(),
				_room_state_observed,
				_four_participants_observed,
				_readiness_observed,
				_point_contest_observed,
				_opening_public_observed,
				_opening_hands_by_adapter.size(),
				_actor_seat_index,
				_actor_play_requested,
				_claim_commit_observed,
				_actor_replacement_observed,
				_claim_requests.size(),
				_claim_confirmations.size(),
				_claim_reveals_by_adapter.size(),
			]
		)

	_finish()


func _read_endpoint() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--endpoint="):
			return argument.trim_prefix("--endpoint=")
	return ""


func _create_participant_adapter(participant_index: int) -> void:
	var adapter := ColyseusRealtimeAdapter.new()
	_adapters.append(adapter)
	root.add_child(adapter)
	adapter.connection_state_changed.connect(
		_on_connection_state_changed.bind(participant_index)
	)
	if participant_index == 0:
		adapter.lobby_rooms_changed.connect(_on_lobby_rooms_changed)
	adapter.game_room_joined.connect(_on_game_room_joined.bind(participant_index))
	adapter.game_room_failed.connect(_on_game_room_failed.bind(participant_index))
	adapter.game_room_state_changed.connect(
		_on_game_room_state_changed.bind(participant_index)
	)
	adapter.match_private_state_changed.connect(
		_on_match_private_state_changed.bind(participant_index)
	)
	adapter.room_action_failed.connect(_on_room_action_failed.bind(participant_index))
	adapter.connect_lobby(_endpoint, PARTICIPANT_NAMES[participant_index])


func _on_connection_state_changed(
	state: String,
	detail: String,
	participant_index: int
) -> void:
	match state:
		"connected":
			_connected_participants[participant_index] = true
			if participant_index > 0 and not _joined_room_ids.has(participant_index):
				_adapters[participant_index].join_game_room(
					_listed_room_id,
					PARTICIPANT_NAMES[participant_index]
				)
		"retryable_error":
			_fail("participant %d lobby connection failed: %s" % [participant_index, detail])


func _on_lobby_rooms_changed(rooms: Array[Dictionary]) -> void:
	if not _connected_participants.has(0):
		return

	if not _initial_rooms_observed:
		if not rooms.is_empty():
			_fail("expected a fresh server to publish an empty initial room list")
			return
		_initial_rooms_observed = true
		_creation_requested = true
		_adapters[0].create_game_room(
			RoomSettings.new(TEST_ROOM_NAME, "two", 60),
			PARTICIPANT_NAMES[0]
		)
		return

	for room in rooms:
		if room.get("name", "") != TEST_ROOM_NAME:
			continue
		if room.get("deck_mode", "") != "two":
			_fail("listed room did not preserve deck mode")
			return
		if room.get("action_deadline_seconds", 0) != 60:
			_fail("listed room did not preserve action deadline")
			return
		if room.get("seat_capacity", 0) != 4:
			_fail("listed room did not expose the four-participant capacity")
			return
		if room.get("participant_count", 0) < 1:
			return
		_listed_room_id = str(room.get("room_id", ""))
		if not _guests_requested:
			_guests_requested = true
			for participant_index in range(1, PARTICIPANT_NAMES.size()):
				_create_participant_adapter(participant_index)
		return


func _on_game_room_joined(room_id: String, participant_index: int) -> void:
	if room_id != _listed_room_id:
		_fail("participant %d joined an unexpected room %s" % [participant_index, room_id])
		return
	_joined_room_ids[participant_index] = room_id


func _on_game_room_failed(message: String, participant_index: int) -> void:
	_fail("participant %d game room request failed: %s" % [participant_index, message])


func _on_game_room_state_changed(state: Dictionary, participant_index: int) -> void:
	var seats: Variant = state.get("seats", [])
	if not seats is Array or seats.size() != 4:
		_fail("participant %d decoded a game state without four seats" % participant_index)
		return
	if state.get("deck_mode", "") != "two" or state.get("action_deadline_seconds", 0) != 60:
		_fail("participant %d decoded incorrect room settings" % participant_index)
		return

	var local_participant_id := str(state.get("local_participant_id", ""))
	if local_participant_id.is_empty():
		_fail("participant %d decoded an empty local participant id" % participant_index)
		return
	_participant_ids_by_adapter[participant_index] = local_participant_id
	if participant_index == 0:
		_room_state_observed = true
		if local_participant_id != str(state.get("host_participant_id", "")):
			_fail("creator was not decoded as the local host")
			return

	if state.get("status", "") == "started":
		if state.get("phase", "") == "claim_reveal":
			_observe_claim_reveal(state, participant_index)
		if participant_index == 0:
			_observe_started_host_state(state, seats)
		_try_request_actor_play()
		_try_request_claims()
		return

	_observe_waiting_state(seats, participant_index, local_participant_id)


func _observe_waiting_state(
	seats: Array,
	participant_index: int,
	local_participant_id: String
) -> void:
	var occupied_count := 0
	var all_ready := true
	var local_seat: Dictionary = {}
	for raw_seat: Variant in seats:
		if not raw_seat is Dictionary:
			continue
		var seat: Dictionary = raw_seat
		if not str(seat.get("participant_id", "")).is_empty():
			occupied_count += 1
			all_ready = all_ready and bool(seat.get("is_ready", false))
		if str(seat.get("participant_id", "")) == local_participant_id:
			local_seat = seat
	if local_seat.is_empty():
		_fail("participant %d could not find its occupied seat" % participant_index)
		return
	if not bool(local_seat.get("is_ready", false)) and not _ready_requested.has(participant_index):
		_ready_requested[participant_index] = true
		_adapters[participant_index].set_ready(true)
	if occupied_count == PARTICIPANT_NAMES.size():
		_four_participants_observed = true
	if (
		participant_index == 0
		and occupied_count == PARTICIPANT_NAMES.size()
		and all_ready
		and _joined_room_ids.size() == PARTICIPANT_NAMES.size()
	):
		_readiness_observed = true
		if not _start_requested:
			_start_requested = true
			_adapters[0].start_match()


func _observe_started_host_state(state: Dictionary, seats: Array) -> void:
	var contest_rounds: Variant = state.get("contest_rounds", [])
	if not contest_rounds is Array or contest_rounds.is_empty():
		_fail("opening did not publish point-contest history")
		return
	for raw_seat: Variant in seats:
		if raw_seat is Dictionary and int(raw_seat.get("hand_count", 0)) != 8:
			_fail("started match did not publish eight-card hand counts")
			return

	var phase := str(state.get("phase", ""))
	match phase:
		"point_contest":
			if state.get("draw_pile_count", -1) != 72:
				_fail("two-deck opening did not leave 72 draw cards")
				return
			_point_contest_observed = true
		"actor_play":
			if state.get("draw_pile_count", -1) != 72:
				_fail("actor-play opening did not preserve 72 draw cards")
				return
			if not _point_contest_observed:
				_fail("actor_play arrived before a visible point_contest phase")
				return
			_actor_seat_index = int(state.get("actor_seat_index", -1))
			if _actor_seat_index < 0 or _actor_seat_index >= seats.size():
				_fail("opening published an invalid actor seat")
				return
			_actor_participant_id = str(seats[_actor_seat_index].get("participant_id", ""))
			if _actor_participant_id.is_empty():
				_fail("opening actor seat was not occupied")
				return
			_opening_public_observed = true
			_try_request_actor_play()
		"claim_commit":
			if int(state.get("turn_number", 0)) != 1:
				_fail("first actor play did not publish turn number 1")
				return
			var played_cards: Variant = state.get("played_cards", [])
			if not played_cards is Array or played_cards.size() != 3:
				_fail("first actor play did not publish exactly three cards")
				return
			var published_card_ids := _card_ids(played_cards)
			var intended_card_ids := _actor_played_card_ids.duplicate()
			published_card_ids.sort()
			intended_card_ids.sort()
			if published_card_ids != intended_card_ids:
				_fail("public played cards did not match the actor intention")
				return
			_claim_commit_observed = true
			_try_request_claims()
		"claim_reveal":
			pass
		_:
			_fail("started room published an unexpected phase: %s" % phase)


func _on_match_private_state_changed(state: Dictionary, participant_index: int) -> void:
	var hand: Variant = state.get("hand", [])
	var participant_id := str(state.get("participant_id", ""))
	if participant_id.is_empty() or not hand is Array or hand.size() != 8:
		_fail("participant %d did not receive a targeted eight-card hand" % participant_index)
		return
	var expected_participant_id := str(_participant_ids_by_adapter.get(participant_index, ""))
	if not expected_participant_id.is_empty() and participant_id != expected_participant_id:
		_fail("participant %d received another participant's private hand" % participant_index)
		return

	_private_message_counts[participant_index] = int(_private_message_counts.get(participant_index, 0)) + 1
	if not _opening_hands_by_adapter.has(participant_index):
		_opening_hands_by_adapter[participant_index] = hand.duplicate(true)
		_private_hand_observed = _opening_hands_by_adapter.size() == PARTICIPANT_NAMES.size()
		_try_request_actor_play()
		return
	if bool(state.get("claim_committed", false)):
		if participant_index == _actor_adapter_index:
			_fail("the actor received a private claim confirmation")
			return
		if not _claim_requests.has(participant_index):
			_fail("participant %d received another participant's claim confirmation" % participant_index)
			return
		if state.get("claim_card_id", "not-null") != null:
			_fail("participant %d pass confirmation exposed a card id" % participant_index)
			return
		_claim_confirmations[participant_index] = true
		return
	if participant_index != _actor_adapter_index:
		_fail("participant %d received an unexpected private match snapshot" % participant_index)
		return
	var replacement_ids := _card_ids(hand)
	for played_card_id in _actor_played_card_ids:
		if replacement_ids.has(played_card_id):
			_fail("actor replacement hand retained a played card")
			return
	_actor_replacement_observed = true
	_try_request_claims()


func _try_request_actor_play() -> void:
	if (
		_actor_play_requested
		or _actor_participant_id.is_empty()
		or _opening_hands_by_adapter.size() != PARTICIPANT_NAMES.size()
	):
		return
	for participant_index in range(PARTICIPANT_NAMES.size()):
		if str(_participant_ids_by_adapter.get(participant_index, "")) != _actor_participant_id:
			continue
		var hand: Variant = _opening_hands_by_adapter.get(participant_index, [])
		if not hand is Array or hand.size() != 8:
			_fail("actor adapter did not retain its targeted opening hand")
			return
		var selected_ids: Array[String] = []
		for card_index in range(3):
			var raw_card: Variant = hand[card_index]
			if not raw_card is Dictionary:
				_fail("actor opening hand contained a malformed card")
				return
			var card_id := str(raw_card.get("id", ""))
			if card_id.is_empty() or selected_ids.has(card_id):
				_fail("actor opening hand contained an invalid physical card id")
				return
			selected_ids.append(card_id)
		_actor_adapter_index = participant_index
		_actor_played_card_ids = selected_ids
		_actor_play_requested = true
		_adapters[participant_index].play_cards(selected_ids)
		return
	_fail("public actor did not map to a connected Native SDK adapter")


func _try_request_claims() -> void:
	if (
		not _claim_commit_observed
		or _actor_adapter_index < 0
		or not _claim_requests.is_empty()
	):
		return
	for participant_index in range(PARTICIPANT_NAMES.size()):
		if participant_index == _actor_adapter_index:
			continue
		_claim_requests[participant_index] = true
		_adapters[participant_index].claim_card(null)


func _observe_claim_reveal(state: Dictionary, participant_index: int) -> void:
	if int(state.get("claim_commit_count", -1)) != 3:
		_fail("participant %d decoded claim_reveal without three commits" % participant_index)
		return
	var revealed_claims: Variant = state.get("revealed_claims", [])
	if not revealed_claims is Array or revealed_claims.size() != 3:
		_fail("participant %d decoded an incomplete public claim reveal" % participant_index)
		return
	for raw_claim: Variant in revealed_claims:
		if not raw_claim is Dictionary or raw_claim.get("card_id", "not-null") != null:
			_fail("participant %d decoded a non-Pass claim in the all-Pass smoke" % participant_index)
			return
	var claim_awards: Variant = state.get("claim_awards", [])
	if not claim_awards is Array or not claim_awards.is_empty():
		_fail("participant %d decoded an award in the all-Pass smoke" % participant_index)
		return
	var discarded_cards: Variant = state.get("discarded_cards", [])
	if not discarded_cards is Array or discarded_cards.size() != 3:
		_fail("participant %d did not decode three public discarded cards" % participant_index)
		return
	var claim_events: Variant = state.get("claim_events", [])
	if not claim_events is Array or claim_events.size() != 1:
		_fail("participant %d did not decode the claims_resolved history" % participant_index)
		return
	var claim_event: Variant = claim_events[0]
	if (
		not claim_event is Dictionary
		or int(claim_event.get("turn_number", 0)) != 1
		or claim_event.get("claims", []).size() != 3
		or not claim_event.get("awards", []).is_empty()
		or claim_event.get("discarded_cards", []).size() != 3
	):
		_fail("participant %d decoded malformed claims_resolved history" % participant_index)
		return
	if not state.get("played_cards", []).is_empty():
		_fail("participant %d retained played cards after claim resolution" % participant_index)
		return
	_claim_reveals_by_adapter[participant_index] = true


func _card_ids(raw_cards: Array) -> Array[String]:
	var result: Array[String] = []
	for raw_card: Variant in raw_cards:
		if raw_card is Dictionary:
			result.append(str(raw_card.get("id", "")))
	return result


func _on_room_action_failed(code: String, message: String, participant_index: int) -> void:
	_fail("participant %d room action failed (%s): %s" % [participant_index, code, message])


func _is_complete() -> bool:
	return (
		_connected_participants.size() == PARTICIPANT_NAMES.size()
		and _initial_rooms_observed
		and _creation_requested
		and _guests_requested
		and not _listed_room_id.is_empty()
		and _joined_room_ids.size() == PARTICIPANT_NAMES.size()
		and _room_state_observed
		and _four_participants_observed
		and _readiness_observed
		and _point_contest_observed
		and _opening_public_observed
		and _private_hand_observed
		and _actor_play_requested
		and _claim_commit_observed
		and _actor_replacement_observed
		and _claim_requests.size() == PARTICIPANT_NAMES.size() - 1
		and _claim_confirmations.size() == PARTICIPANT_NAMES.size() - 1
		and _claim_reveals_by_adapter.size() == PARTICIPANT_NAMES.size()
	)


func _fail(message: String) -> void:
	if _failure.is_empty():
		_failure = message


func _finish() -> void:
	for adapter in _adapters:
		if adapter != null and is_instance_valid(adapter):
			adapter.disconnect_game_room()
			adapter.disconnect_lobby(false)
	await create_timer(0.25).timeout
	for frame in range(5):
		await process_frame
	for adapter in _adapters:
		if adapter != null and is_instance_valid(adapter):
			adapter.queue_free()
	await process_frame
	await process_frame

	if _failure.is_empty():
		print(
			(
				"PASS: four Native SDK participants joined and readied room %s, "
				+ "actor seat %d played three targeted private cards, three non-actors privately "
				+ "confirmed Pass, and all clients decoded claim_reveal with claimEvents/discards"
			) % [_listed_room_id, _actor_seat_index]
		)
		quit(0)
		return

	push_error("FAIL: %s" % _failure)
	quit(1)
