extends SceneTree

const ColyseusRealtimeAdapter = preload("res://scripts/network/colyseus_realtime_adapter.gd")
const TEST_TIMEOUT_SECONDS := 12.0
const TEST_ROOM_NAME := "Native SDK smoke room"

var _adapter: ColyseusRealtimeAdapter
var _deadline_msec := 0
var _connected := false
var _initial_rooms_observed := false
var _creation_requested := false
var _listed_room_id := ""
var _joined_room_id := ""
var _room_state_observed := false
var _fill_bots_requested := false
var _bots_observed := false
var _readiness_requested := false
var _readiness_observed := false
var _start_requested := false
var _point_contest_observed := false
var _opening_public_observed := false
var _private_hand_observed := false
var _failure := ""


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var endpoint := _read_endpoint()
	if endpoint.is_empty():
		_fail("missing --endpoint=ws://host:port")
		_finish()
		return

	_adapter = ColyseusRealtimeAdapter.new()
	root.add_child(_adapter)
	_adapter.connection_state_changed.connect(_on_connection_state_changed)
	_adapter.lobby_rooms_changed.connect(_on_lobby_rooms_changed)
	_adapter.game_room_joined.connect(_on_game_room_joined)
	_adapter.game_room_failed.connect(_on_game_room_failed)
	_adapter.game_room_state_changed.connect(_on_game_room_state_changed)
	_adapter.match_private_state_changed.connect(_on_match_private_state_changed)
	_adapter.room_action_failed.connect(_on_room_action_failed)

	_deadline_msec = Time.get_ticks_msec() + int(TEST_TIMEOUT_SECONDS * 1000.0)
	_adapter.connect_lobby(endpoint, "Smoke Participant")

	while _failure.is_empty() and not _is_complete() and Time.get_ticks_msec() < _deadline_msec:
		await process_frame

	if _failure.is_empty() and not _is_complete():
		_fail(
			"timed out waiting for live lobby flow "
			+ "(connected=%s, initial=%s, listed=%s, joined=%s, state=%s, "
			+ "bots=%s, ready=%s, point_contest=%s, opening=%s, private=%s)"
			% [
				_connected,
				_initial_rooms_observed,
				_listed_room_id,
				_joined_room_id,
				_room_state_observed,
				_bots_observed,
				_readiness_observed,
				_point_contest_observed,
				_opening_public_observed,
				_private_hand_observed,
			]
		)

	_finish()


func _read_endpoint() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--endpoint="):
			return argument.trim_prefix("--endpoint=")
	return ""


func _on_connection_state_changed(state: String, detail: String) -> void:
	match state:
		"connected":
			_connected = true
		"retryable_error":
			_fail("lobby connection failed: %s" % detail)


func _on_lobby_rooms_changed(rooms: Array[Dictionary]) -> void:
	# connect_lobby() first publishes its local reset. Only a list received after
	# the joined signal can satisfy the server-backed initial-list assertion.
	if not _connected:
		return

	if not _initial_rooms_observed:
		if not rooms.is_empty():
			_fail("expected a fresh server to publish an empty initial room list")
			return
		_initial_rooms_observed = true
		_creation_requested = true
		_adapter.create_game_room(
			RoomSettings.new(TEST_ROOM_NAME, "two", 60),
			"Smoke Participant"
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
		# Colyseus first advertises the room with zero participants, then publishes
		# the joined-participant count as a second live listing update.
		if room.get("participant_count", 0) != 1:
			return
		_listed_room_id = room.get("room_id", "")
		if _room_state_observed and not _fill_bots_requested:
			_fill_bots_requested = true
			_adapter.fill_bots()


func _on_game_room_joined(room_id: String) -> void:
	_joined_room_id = room_id


func _on_game_room_failed(message: String) -> void:
	_fail("game room creation failed: %s" % message)


func _on_game_room_state_changed(state: Dictionary) -> void:
	var seats: Variant = state.get("seats", [])
	if not seats is Array or seats.size() != 4:
		_fail("decoded game room state did not contain four seats: %s" % [state])
		return
	if state.get("local_participant_id", "") != state.get("host_participant_id", ""):
		_fail("creator was not decoded as the local host")
		return
	if state.get("deck_mode", "") != "two" or state.get("action_deadline_seconds", 0) != 60:
		_fail("decoded game room state did not preserve settings")
		return

	_room_state_observed = true
	if state.get("status", "") == "started":
		if state.get("draw_pile_count", -1) != 72:
			_fail("two-deck opening did not leave 72 draw cards")
			return
		var contest_rounds: Variant = state.get("contest_rounds", [])
		if not contest_rounds is Array or contest_rounds.is_empty():
			_fail("opening did not publish point-contest history")
			return
		for seat: Dictionary in seats:
			if int(seat.get("hand_count", 0)) != 8:
				_fail("opening did not publish eight-card hand counts")
				return
		var phase := str(state.get("phase", ""))
		if phase == "point_contest":
			_point_contest_observed = true
			return
		if phase != "actor_play":
			_fail("started room published an unknown opening phase: %s" % phase)
			return
		if not _point_contest_observed:
			_fail("actor_play arrived before a visible point_contest phase")
			return
		_opening_public_observed = true
		return

	var occupied_count := 0
	for seat: Dictionary in seats:
		if not str(seat.get("participant_id", "")).is_empty():
			occupied_count += 1
	if occupied_count < 4:
		if not _listed_room_id.is_empty() and not _fill_bots_requested:
			_fill_bots_requested = true
			_adapter.fill_bots()
		return
	_bots_observed = true
	var local_participant_id := str(state.get("local_participant_id", ""))
	for seat: Dictionary in seats:
		if str(seat.get("participant_id", "")) != local_participant_id:
			continue
		if bool(seat.get("is_ready", false)):
			_readiness_observed = true
			if not _start_requested:
				_start_requested = true
				_adapter.start_match()
		elif not _readiness_requested:
			_readiness_requested = true
			_adapter.set_ready(true)
		return
	_fail("decoded game room state did not contain the local seat")


func _on_match_private_state_changed(state: Dictionary) -> void:
	var hand: Variant = state.get("hand", [])
	if state.get("participant_id", "") != "" and hand is Array and hand.size() == 8:
		_private_hand_observed = true
		return
	_fail("private opening state did not contain the local eight-card hand")


func _on_room_action_failed(code: String, message: String) -> void:
	_fail("room action failed (%s): %s" % [code, message])


func _is_complete() -> bool:
	return (
		_connected
		and _initial_rooms_observed
		and _creation_requested
		and not _listed_room_id.is_empty()
		and _listed_room_id == _joined_room_id
		and _room_state_observed
		and _bots_observed
		and _readiness_observed
		and _point_contest_observed
		and _opening_public_observed
		and _private_hand_observed
	)


func _fail(message: String) -> void:
	if _failure.is_empty():
		_failure = message


func _finish() -> void:
	if _adapter != null and is_instance_valid(_adapter):
		_adapter.disconnect_game_room()
		_adapter.disconnect_lobby(false)
		await create_timer(0.25).timeout
		for frame in range(5):
			await process_frame
		_adapter.queue_free()
		await process_frame
		await process_frame

	if _failure.is_empty():
		print(
			(
				"PASS: native SDK created and listed game room %s, decoded four seats, "
				+ "synchronized readiness, opened the match, and received one private hand"
			) % _joined_room_id
		)
		quit(0)
		return

	push_error("FAIL: %s" % _failure)
	quit(1)
