extends Node
class_name ColyseusRealtimeAdapter

signal connection_state_changed(state: String, detail: String)
signal lobby_rooms_changed(rooms: Array[Dictionary])
signal game_room_joined(room_id: String)
signal game_room_failed(message: String)
signal game_room_state_changed(state: Dictionary)
signal match_private_state_changed(state: Dictionary)
signal game_room_left(code: int, reason: String)
signal game_room_connection_changed(state: String, detail: String)
signal room_action_failed(code: String, message: String)

const ColyseusSdk = preload("res://addons/colyseus/colyseus.gd")
const CombinationCatalog = preload("res://scripts/domain/combination_catalog.gd")
const GameSchema = preload("res://schema/schema.gd")
const LOBBY_ROOM_TYPE := "lobby"
const GAME_ROOM_TYPE := "game"
const ROOM_SEAT_COUNT := 4
const MAX_DECK_CARD_COUNT := 104

var _client: Variant
var _lobby_room: Variant
var _game_room: Variant
var _pending_game_room: Variant
var _game_room_callbacks: Dictionary = {}
var _rooms_by_id: Dictionary = {}
var _connected := false


func connect_lobby(endpoint: String, nickname: String) -> void:
	disconnect_lobby(false)
	connection_state_changed.emit("connecting", "")

	if not ClassDB.class_exists(&"_ColyseusClient"):
		connection_state_changed.emit("retryable_error", "Colyseus 扩展未加载")
		return

	_client = ColyseusSdk.Client.new(endpoint)
	_lobby_room = _client.join_or_create(LOBBY_ROOM_TYPE, {"nickname": nickname})
	if _lobby_room == null:
		connection_state_changed.emit("retryable_error", "无法创建大厅连接")
		return

	var observed_room: Variant = _lobby_room
	observed_room.joined.connect(_on_lobby_joined.bind(observed_room))
	observed_room.message_received.connect(_on_lobby_message.bind(observed_room))
	observed_room.error.connect(_on_lobby_error.bind(observed_room))
	observed_room.left.connect(_on_lobby_left.bind(observed_room))
	observed_room.dropped.connect(_on_lobby_dropped.bind(observed_room))
	observed_room.reconnected.connect(_on_lobby_reconnected.bind(observed_room))


func disconnect_lobby(announce := true) -> void:
	var previous_room: Variant = _lobby_room
	_lobby_room = null
	_connected = false
	_rooms_by_id.clear()
	_publish_rooms()
	if previous_room != null:
		previous_room.leave()
	if announce:
		connection_state_changed.emit("disconnected", "")


func disconnect_game_room() -> void:
	_leave_game_room(false)


func leave_game_room() -> void:
	_leave_game_room(true)


func _leave_game_room(announce: bool) -> void:
	var previous_room: Variant = _game_room
	var pending_room: Variant = _pending_game_room
	_game_room = null
	_pending_game_room = null
	if pending_room != null and pending_room != previous_room:
		_dispose_game_room(pending_room, true)
	if previous_room != null:
		_dispose_game_room(previous_room, true)
	if announce:
		game_room_left.emit(1000, "")


func create_game_room(
	settings: RoomSettings,
	nickname: String
) -> void:
	if not _connected or _client == null:
		_cancel_pending_game_room()
		game_room_failed.emit("请先连接服务器")
		return
	var options := {
		"nickname": nickname,
		"displayName": settings.display_name,
		"deckMode": settings.deck_mode,
		"actionDeadlineSeconds": settings.action_deadline_seconds,
	}
	_watch_game_room(_client.create(GAME_ROOM_TYPE, options))


func join_game_room(room_id: String, nickname: String) -> void:
	if not _connected or _client == null:
		_cancel_pending_game_room()
		game_room_failed.emit("请先连接服务器")
		return
	_watch_game_room(_client.join_by_id(room_id, {"nickname": nickname}))


func set_ready(ready: bool) -> void:
	_send_game_room_message("set_ready", {"ready": ready})


func configure_room(configuration: Object) -> void:
	_send_game_room_message("configure", {
		"deckMode": configuration.deck_mode,
		"actionDeadlineSeconds": configuration.action_deadline_seconds,
	})


func fill_bots() -> void:
	_send_game_room_message("fill_bots")


func start_match() -> void:
	_send_game_room_message("start")


func play_cards(card_ids: Array[String]) -> void:
	_send_game_room_message("play_cards", {"cardIds": card_ids.duplicate()})


func claim_card(card_id: Variant) -> void:
	_send_game_room_message("claim", {"cardId": card_id})


func discard_card(card_id: String, turn_number: int) -> void:
	_send_game_room_message("discard", {
		"cardId": card_id,
		"turnNumber": turn_number,
	})


func submit_final_selection(groups: Array) -> void:
	_send_game_room_message("final_selection", {
		"mode": "manual",
		"groups": groups.duplicate(true),
	})


func submit_best_final_selection() -> void:
	_send_game_room_message("final_selection", {"mode": "best"})


func _exit_tree() -> void:
	disconnect_game_room()
	disconnect_lobby(false)


func _watch_game_room(room: Variant) -> void:
	if room == null:
		_cancel_pending_game_room()
		game_room_failed.emit("房间请求未能发出")
		return
	# Keep the currently joined room authoritative until this candidate completes
	# its handshake. A stale/full/locked join can therefore never replace it.
	_cancel_pending_game_room()
	_pending_game_room = room
	room.set_state_type(GameSchema.GameRoomState)
	_connect_game_room_callbacks(room)


func _cancel_pending_game_room() -> void:
	var pending_room: Variant = _pending_game_room
	_pending_game_room = null
	if pending_room != null:
		_dispose_game_room(pending_room, true)


func _connect_game_room_callbacks(room: Variant) -> void:
	var joined_callback := _on_game_room_joined.bind(room)
	var state_callback := _on_game_room_state_changed.bind(room)
	var message_callback := _on_game_room_message.bind(room)
	var error_callback := _on_game_room_error.bind(room)
	var left_callback := _on_game_room_left.bind(room)
	var dropped_callback := _on_game_room_dropped.bind(room)
	var reconnected_callback := _on_game_room_reconnected.bind(room)
	room.joined.connect(joined_callback)
	room.state_changed.connect(state_callback)
	room.message_received.connect(message_callback)
	room.error.connect(error_callback)
	room.left.connect(left_callback)
	room.dropped.connect(dropped_callback)
	room.reconnected.connect(reconnected_callback)
	_game_room_callbacks[_game_room_key(room)] = [
		[&"joined", joined_callback],
		[&"state_changed", state_callback],
		[&"message_received", message_callback],
		[&"error", error_callback],
		[&"left", left_callback],
		[&"dropped", dropped_callback],
		[&"reconnected", reconnected_callback],
	]


func _dispose_game_room(room: Variant, leave: bool) -> void:
	_disconnect_game_room_callbacks(room)
	if not leave or room == null:
		return
	if room is Object and not is_instance_valid(room):
		return
	room.leave()


func _disconnect_game_room_callbacks(room: Variant) -> void:
	if room == null:
		return
	var key := _game_room_key(room)
	var callbacks: Variant = _game_room_callbacks.get(key, [])
	_game_room_callbacks.erase(key)
	if not callbacks is Array:
		return
	if room is Object and not is_instance_valid(room):
		return
	for entry: Variant in callbacks:
		if not entry is Array or entry.size() != 2:
			continue
		var signal_name: StringName = entry[0]
		var callback: Callable = entry[1]
		if room.has_signal(signal_name) and room.is_connected(signal_name, callback):
			room.disconnect(signal_name, callback)


func _game_room_key(room: Variant) -> int:
	if room is Object:
		return room.get_instance_id()
	return 0


func _on_lobby_joined(room: Variant) -> void:
	if room != _lobby_room:
		return
	_connected = true
	connection_state_changed.emit("connected", "")


func _on_lobby_error(_code: int, message: String, room: Variant) -> void:
	if room != _lobby_room:
		return
	_connected = false
	connection_state_changed.emit("retryable_error", message)


func _on_lobby_left(_code: int, reason: String, room: Variant) -> void:
	if room != _lobby_room:
		return
	_connected = false
	_lobby_room = null
	_rooms_by_id.clear()
	_publish_rooms()
	connection_state_changed.emit("disconnected", reason)


func _on_lobby_dropped(_code: int, _reason: String, room: Variant) -> void:
	if room == _lobby_room:
		connection_state_changed.emit("connecting", "")


func _on_lobby_reconnected(room: Variant) -> void:
	if room == _lobby_room:
		_connected = true
		connection_state_changed.emit("connected", "")


func _on_lobby_message(type: Variant, data: Variant, room: Variant) -> void:
	if room != _lobby_room:
		return
	match str(type):
		"rooms":
			_replace_rooms(data)
		"+":
			_apply_room_patch(data)
		"-":
			_remove_room(data)


func _replace_rooms(data: Variant) -> void:
	_rooms_by_id.clear()
	if data is Array:
		for raw_room: Variant in data:
			_upsert_room(raw_room)
	_publish_rooms()


func _apply_room_patch(data: Variant) -> void:
	if not data is Array or data.size() < 2:
		return
	var raw_room: Variant = data[1]
	if raw_room is Dictionary and not raw_room.has("roomId"):
		raw_room = raw_room.duplicate(true)
		raw_room["roomId"] = str(data[0])
	_upsert_room(raw_room)
	_publish_rooms()


func _remove_room(data: Variant) -> void:
	var room_id := str(data[0]) if data is Array and not data.is_empty() else str(data)
	_rooms_by_id.erase(room_id)
	_publish_rooms()


func _upsert_room(raw_room: Variant) -> void:
	if not raw_room is Dictionary:
		return
	var normalized := _normalize_joinable_room(raw_room)
	var room_id := str(_read(raw_room, "roomId", "room_id", ""))
	if normalized.is_empty():
		_rooms_by_id.erase(room_id)
		return
	_rooms_by_id[normalized["room_id"]] = normalized


func _normalize_joinable_room(raw_room: Dictionary) -> Dictionary:
	var room_id := str(_read(raw_room, "roomId", "room_id", ""))
	var seat_capacity := int(_read(raw_room, "maxClients", "max_clients", 4))
	var locked := bool(_read(raw_room, "locked", "locked", false))
	var is_private := bool(_read(raw_room, "private", "private", false))
	var metadata: Variant = _read(raw_room, "metadata", "metadata", {})
	if metadata is String:
		metadata = JSON.parse_string(metadata)
	if not metadata is Dictionary:
		metadata = {}
	var participant_count := int(_read(
		metadata,
		"participantCount",
		"participant_count",
		_read(raw_room, "clients", "clients", 0)
	))
	var status := str(_read(metadata, "status", "status", "waiting"))

	if room_id.is_empty() or locked or is_private or participant_count >= seat_capacity or status != "waiting":
		return {}

	return {
		"room_id": room_id,
		"name": str(_read(metadata, "displayName", "display_name", "未命名房间")),
		"participant_count": participant_count,
		"seat_capacity": seat_capacity,
		"deck_mode": str(_read(metadata, "deckMode", "deck_mode", "one")),
		"action_deadline_seconds": int(_read(metadata, "actionDeadlineSeconds", "action_deadline_seconds", 30)),
	}


func _publish_rooms() -> void:
	var rooms: Array[Dictionary] = []
	for value: Variant in _rooms_by_id.values():
		if value is Dictionary:
			rooms.append(value.duplicate(true))
	rooms.sort_custom(_sort_rooms)
	lobby_rooms_changed.emit(rooms)


func _sort_rooms(left: Dictionary, right: Dictionary) -> bool:
	var name_order := str(left["name"]).naturalnocasecmp_to(str(right["name"]))
	if name_order == 0:
		return str(left["room_id"]) < str(right["room_id"])
	return name_order < 0


func _read(source: Dictionary, primary: String, alternate: String, fallback: Variant) -> Variant:
	if source.has(primary):
		return source[primary]
	if source.has(alternate):
		return source[alternate]
	return fallback


func _on_game_room_joined(room: Variant) -> void:
	if room != _pending_game_room:
		return
	var previous_room: Variant = _game_room
	_pending_game_room = null
	if previous_room != null and previous_room != room:
		_dispose_game_room(previous_room, true)
	_game_room = room
	game_room_joined.emit(room.get_id())
	game_room_connection_changed.emit("connected", "")


func _on_game_room_error(_code: int, message: String, room: Variant) -> void:
	if room == _pending_game_room:
		_pending_game_room = null
		_dispose_game_room(room, true)
		game_room_failed.emit(message)
		return
	if room == _game_room:
		game_room_failed.emit(message)


func _on_game_room_state_changed(room: Variant) -> void:
	if room != _game_room:
		return
	var snapshot := _normalize_game_room_state(room.get_state(), room)
	if not snapshot.is_empty():
		game_room_state_changed.emit(snapshot)


func _on_game_room_message(type: Variant, data: Variant, room: Variant) -> void:
	if room != _game_room:
		return
	match str(type):
		"room_error":
			if not data is Dictionary:
				room_action_failed.emit("unknown", str(data))
				return
			room_action_failed.emit(
				str(data.get("code", "unknown")),
				str(data.get("message", "房间操作失败"))
			)
		"match_private_state":
			var snapshot := _normalize_match_private_state(data, room)
			if not snapshot.is_empty():
				match_private_state_changed.emit(snapshot)


func _on_game_room_left(code: int, reason: String, room: Variant) -> void:
	if room == _pending_game_room:
		_pending_game_room = null
		_dispose_game_room(room, false)
		game_room_failed.emit(reason if not reason.is_empty() else "房间连接已关闭")
		return
	if room != _game_room:
		return
	_game_room = null
	_dispose_game_room(room, false)
	game_room_connection_changed.emit("disconnected", reason)
	game_room_left.emit(code, reason)


func _on_game_room_dropped(_code: int, reason: String, room: Variant) -> void:
	if room == _game_room:
		game_room_connection_changed.emit("reconnecting", reason)


func _on_game_room_reconnected(room: Variant) -> void:
	if room == _game_room:
		game_room_connection_changed.emit("connected", "")


func _send_game_room_message(type: String, payload: Variant = null) -> void:
	if _game_room == null:
		room_action_failed.emit("not_joined", "尚未加入房间")
		return
	_game_room.send_message(type, payload)


func _normalize_game_room_state(raw_state: Variant, room: Variant) -> Dictionary:
	if raw_state is Object and raw_state.has_method("to_dictionary"):
		raw_state = raw_state.to_dictionary()
	if not raw_state is Dictionary:
		return {}

	# The beta native decoder may repeat an array tail; stable seat indexes keep
	# the application snapshot at the server's fixed four-seat contract.
	var seats_by_index: Dictionary = {}
	var raw_seats: Variant = raw_state.get("seats", [])
	if raw_seats is Array:
		for raw_seat: Variant in raw_seats:
			if raw_seat is Object and raw_seat.has_method("to_dictionary"):
				raw_seat = raw_seat.to_dictionary()
			if raw_seat is Dictionary:
				var seat_index := int(raw_seat.get("seatIndex", -1))
				if seat_index < 0 or seat_index >= ROOM_SEAT_COUNT:
					continue
				seats_by_index[seat_index] = {
					"seat_index": seat_index,
					"participant_id": str(raw_seat.get("participantId", "")),
					"nickname": str(raw_seat.get("nickname", "")),
					"is_bot": bool(raw_seat.get("bot", false)),
					"is_ready": bool(raw_seat.get("ready", false)),
					"score": int(raw_seat.get("score", 0)),
					"hand_count": int(raw_seat.get("handCount", 0)),
				}
	var seats: Array[Dictionary] = []
	for seat_index in range(ROOM_SEAT_COUNT):
		seats.append(seats_by_index.get(seat_index, {
			"seat_index": seat_index,
			"participant_id": "",
			"nickname": "",
			"is_bot": false,
			"is_ready": false,
			"score": 0,
			"hand_count": 0,
		}))

	return {
		"room_id": room.get_id(),
		"local_participant_id": room.get_session_id(),
		"status": str(raw_state.get("status", "")),
		"display_name": str(raw_state.get("displayName", "")),
		"deck_mode": str(raw_state.get("deckMode", "one")),
		"action_deadline_seconds": int(raw_state.get("actionDeadlineSeconds", 30)),
		"host_participant_id": str(raw_state.get("hostParticipantId", "")),
		"phase": str(raw_state.get("phase", "")),
		"actor_seat_index": int(raw_state.get("actorSeatIndex", -1)),
		"first_actor_seat_index": int(raw_state.get("firstActorSeatIndex", -1)),
		"draw_pile_count": int(raw_state.get("drawPileCount", 0)),
		"turn_number": maxi(0, int(raw_state.get("turnNumber", 0))),
		"played_cards": _normalize_public_cards(raw_state.get("playedCards", []), 3),
		"played_category": _normalize_combination_category(raw_state.get("playedCategory", "")),
		"played_score": maxi(0, int(raw_state.get("playedScore", 0))),
		"play_events": _normalize_play_events(raw_state.get("playEvents", [])),
		"revealed_claims": _normalize_revealed_claims(raw_state.get("revealedClaims", [])),
		"claim_awards": _normalize_claim_awards(raw_state.get("claimAwards", [])),
		"discarded_cards": _normalize_public_cards(raw_state.get("discardedCards", []), MAX_DECK_CARD_COUNT),
		"sealed_card_count": maxi(0, int(raw_state.get("sealedCardCount", 0))),
		"pending_discard_seat_indexes": _normalize_seat_indexes(
			raw_state.get("pendingDiscardSeatIndexes", [])
		),
		"claim_events": _normalize_claim_events(raw_state.get("claimEvents", [])),
		"discard_events": _normalize_discard_events(raw_state.get("discardEvents", [])),
		"final_results": _normalize_final_results(raw_state.get("finalResults", [])),
		"winner_seat_indexes": _normalize_seat_indexes(raw_state.get("winnerSeatIndexes", [])),
		"final_events": _normalize_final_events(raw_state.get("finalEvents", [])),
		"seats": seats,
		"contest_rounds": _normalize_contest_rounds(raw_state.get("contestRounds", [])),
	}


func _normalize_contest_rounds(raw_rounds: Variant) -> Array[Dictionary]:
	var rounds_by_index: Dictionary = {}
	if not raw_rounds is Array:
		return []
	for raw_round: Variant in raw_rounds:
		raw_round = _dictionary_from_schema(raw_round)
		if not raw_round is Dictionary:
			continue
		var round_index := int(raw_round.get("roundIndex", -1))
		if round_index < 0:
			continue
		var reveals_by_seat: Dictionary = {}
		var raw_reveals: Variant = raw_round.get("reveals", [])
		if raw_reveals is Array:
			for raw_reveal: Variant in raw_reveals:
				raw_reveal = _dictionary_from_schema(raw_reveal)
				if not raw_reveal is Dictionary:
					continue
				var seat_index := int(raw_reveal.get("seatIndex", -1))
				if seat_index < 0 or seat_index >= ROOM_SEAT_COUNT:
					continue
				var card := _normalize_card(raw_reveal.get("card", {}))
				if card.is_empty():
					continue
				reveals_by_seat[seat_index] = {
					"seat_index": seat_index,
					"card": card,
				}
		var reveals: Array[Dictionary] = []
		var reveal_seats := reveals_by_seat.keys()
		reveal_seats.sort()
		for seat_index: Variant in reveal_seats:
			reveals.append(reveals_by_seat[seat_index])
		var tied_seat_indexes: Array[int] = []
		var raw_tied_seats: Variant = raw_round.get("tiedSeatIndexes", [])
		if raw_tied_seats is Array:
			for raw_seat_index: Variant in raw_tied_seats:
				var seat_index := int(raw_seat_index)
				if (
					seat_index >= 0
					and seat_index < ROOM_SEAT_COUNT
					and not tied_seat_indexes.has(seat_index)
				):
					tied_seat_indexes.append(seat_index)
		tied_seat_indexes.sort()
		rounds_by_index[round_index] = {
			"round_index": round_index,
			"reveals": reveals,
			"tied_seat_indexes": tied_seat_indexes,
			"winner_seat_index": int(raw_round.get("winnerSeatIndex", -1)),
		}
	var result: Array[Dictionary] = []
	var round_indexes := rounds_by_index.keys()
	round_indexes.sort()
	for round_index: Variant in round_indexes:
		result.append(rounds_by_index[round_index])
	return result


func _normalize_card(raw_card: Variant) -> Dictionary:
	raw_card = _dictionary_from_schema(raw_card)
	if not raw_card is Dictionary:
		return {}
	var card_id := str(raw_card.get("id", ""))
	var rank := int(raw_card.get("rank", 0))
	var suit := str(raw_card.get("suit", ""))
	if card_id.is_empty() or rank < 2 or rank > 14:
		return {}
	if suit not in ["clubs", "spades", "diamonds", "hearts"]:
		return {}
	return {
		"id": card_id,
		"rank": rank,
		"suit": suit,
		"copy_index": int(raw_card.get("copyIndex", 0)),
	}


func _normalize_public_cards(raw_cards: Variant, limit: int) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	var seen_card_ids: Dictionary = {}
	if not raw_cards is Array:
		return cards
	for raw_card: Variant in raw_cards:
		var card := _normalize_card(raw_card)
		if card.is_empty() or seen_card_ids.has(card["id"]):
			continue
		seen_card_ids[card["id"]] = true
		cards.append(card)
		if cards.size() >= limit:
			break
	return cards


func _normalize_seat_indexes(raw_seat_indexes: Variant) -> Array[int]:
	var seat_indexes: Array[int] = []
	if not raw_seat_indexes is Array:
		return seat_indexes
	for raw_seat_index: Variant in raw_seat_indexes:
		var seat_index := int(raw_seat_index)
		if seat_index < 0 or seat_index >= ROOM_SEAT_COUNT or seat_indexes.has(seat_index):
			continue
		seat_indexes.append(seat_index)
	seat_indexes.sort()
	return seat_indexes


func _normalize_combination_category(raw_category: Variant) -> String:
	var category := str(raw_category)
	return category if CombinationCatalog.is_category(category) else ""


func _normalize_play_events(raw_events: Variant) -> Array[Dictionary]:
	var events_by_turn: Dictionary = {}
	if not raw_events is Array:
		return []
	for raw_event: Variant in raw_events:
		raw_event = _dictionary_from_schema(raw_event)
		if not raw_event is Dictionary:
			continue
		var turn_number := int(raw_event.get("turnNumber", 0))
		var actor_seat_index := int(raw_event.get("actorSeatIndex", -1))
		var cards := _normalize_public_cards(raw_event.get("cards", []), 3)
		var category := _normalize_combination_category(raw_event.get("category", ""))
		if (
			turn_number <= 0
			or actor_seat_index < 0
			or actor_seat_index >= ROOM_SEAT_COUNT
			or cards.size() != 3
			or category.is_empty()
		):
			continue
		events_by_turn[turn_number] = {
			"turn_number": turn_number,
			"actor_seat_index": actor_seat_index,
			"cards": cards,
			"category": category,
			"score": maxi(0, int(raw_event.get("score", 0))),
		}
	var result: Array[Dictionary] = []
	var turn_numbers := events_by_turn.keys()
	turn_numbers.sort()
	for turn_number: Variant in turn_numbers:
		result.append(events_by_turn[turn_number])
	return result


func _normalize_revealed_claims(raw_claims: Variant) -> Array[Dictionary]:
	var claims_by_seat: Dictionary = {}
	if not raw_claims is Array:
		return []
	for raw_claim: Variant in raw_claims:
		raw_claim = _dictionary_from_schema(raw_claim)
		if not raw_claim is Dictionary:
			continue
		var seat_index := int(raw_claim.get("seatIndex", -1))
		if seat_index < 0 or seat_index >= ROOM_SEAT_COUNT:
			continue
		var passed := bool(raw_claim.get("passed", false))
		var card_id := str(raw_claim.get("cardId", ""))
		if not passed and card_id.is_empty():
			continue
		claims_by_seat[seat_index] = {
			"seat_index": seat_index,
			"card_id": null if passed else card_id,
		}
	var result: Array[Dictionary] = []
	var seat_indexes := claims_by_seat.keys()
	seat_indexes.sort()
	for seat_index: Variant in seat_indexes:
		result.append(claims_by_seat[seat_index])
	return result


func _normalize_claim_awards(raw_awards: Variant) -> Array[Dictionary]:
	var awards_by_seat: Dictionary = {}
	if not raw_awards is Array:
		return []
	for raw_award: Variant in raw_awards:
		raw_award = _dictionary_from_schema(raw_award)
		if not raw_award is Dictionary:
			continue
		var seat_index := int(raw_award.get("seatIndex", -1))
		var source := str(raw_award.get("source", ""))
		var card := _normalize_card(raw_award.get("card", {}))
		if (
			seat_index < 0
			or seat_index >= ROOM_SEAT_COUNT
			or source not in ["unique", "collision"]
			or card.is_empty()
		):
			continue
		awards_by_seat[seat_index] = {
			"seat_index": seat_index,
			"card": card,
			"source": source,
		}
	var result: Array[Dictionary] = []
	var seat_indexes := awards_by_seat.keys()
	seat_indexes.sort()
	for seat_index: Variant in seat_indexes:
		result.append(awards_by_seat[seat_index])
	return result


func _normalize_claim_events(raw_events: Variant) -> Array[Dictionary]:
	var events_by_turn: Dictionary = {}
	if not raw_events is Array:
		return []
	for raw_event: Variant in raw_events:
		raw_event = _dictionary_from_schema(raw_event)
		if not raw_event is Dictionary:
			continue
		var turn_number := int(raw_event.get("turnNumber", 0))
		var claims := _normalize_revealed_claims(raw_event.get("claims", []))
		if turn_number <= 0 or claims.size() != 3:
			continue
		events_by_turn[turn_number] = {
			"turn_number": turn_number,
			"claims": claims,
			"awards": _normalize_claim_awards(raw_event.get("awards", [])),
			"discarded_cards": _normalize_public_cards(raw_event.get("discardedCards", []), 3),
		}
	var result: Array[Dictionary] = []
	var turn_numbers := events_by_turn.keys()
	turn_numbers.sort()
	for turn_number: Variant in turn_numbers:
		result.append(events_by_turn[turn_number])
	return result


func _normalize_discard_events(raw_events: Variant) -> Array[Dictionary]:
	var events_by_turn_and_seat: Dictionary = {}
	if not raw_events is Array:
		return []
	for raw_event: Variant in raw_events:
		raw_event = _dictionary_from_schema(raw_event)
		if not raw_event is Dictionary:
			continue
		var turn_number := int(raw_event.get("turnNumber", 0))
		var seat_index := int(raw_event.get("seatIndex", -1))
		var card := _normalize_card(raw_event.get("card", {}))
		if (
			turn_number <= 0
			or seat_index < 0
			or seat_index >= ROOM_SEAT_COUNT
			or card.is_empty()
		):
			continue
		events_by_turn_and_seat["%d:%d" % [turn_number, seat_index]] = {
			"turn_number": turn_number,
			"seat_index": seat_index,
			"card": card,
		}
	var result: Array[Dictionary] = []
	for event: Variant in events_by_turn_and_seat.values():
		result.append(event)
	result.sort_custom(_discard_event_before)
	return result


func _discard_event_before(left: Dictionary, right: Dictionary) -> bool:
	var left_turn := int(left.get("turn_number", 0))
	var right_turn := int(right.get("turn_number", 0))
	if left_turn == right_turn:
		return int(left.get("seat_index", -1)) < int(right.get("seat_index", -1))
	return left_turn < right_turn


func _normalize_final_results(raw_results: Variant) -> Array[Dictionary]:
	var results_by_seat: Dictionary = {}
	if not raw_results is Array:
		return []
	for raw_result: Variant in raw_results:
		raw_result = _dictionary_from_schema(raw_result)
		if not raw_result is Dictionary:
			continue
		var seat_index := int(raw_result.get("seatIndex", -1))
		var raw_groups: Variant = raw_result.get("groups", [])
		if seat_index < 0 or seat_index >= ROOM_SEAT_COUNT or not raw_groups is Array:
			continue
		if raw_groups.size() != 2:
			continue
		var groups: Array[Dictionary] = []
		var selected_card_ids: Dictionary = {}
		var valid := true
		for raw_group: Variant in raw_groups:
			raw_group = _dictionary_from_schema(raw_group)
			if not raw_group is Dictionary:
				valid = false
				break
			var cards := _normalize_public_cards(raw_group.get("cards", []), 3)
			var category := _normalize_combination_category(raw_group.get("category", ""))
			if cards.size() != 3 or category.is_empty():
				valid = false
				break
			for card in cards:
				var card_id := str(card.get("id", ""))
				if selected_card_ids.has(card_id):
					valid = false
					break
				selected_card_ids[card_id] = true
			if not valid:
				break
			groups.append({
				"cards": cards,
				"category": category,
				"score": maxi(0, int(raw_group.get("score", 0))),
			})
		if not valid or groups.size() != 2:
			continue
		results_by_seat[seat_index] = {
			"seat_index": seat_index,
			"groups": groups,
			"total_score": maxi(0, int(raw_result.get("totalScore", 0))),
		}
	var results: Array[Dictionary] = []
	var seat_indexes := results_by_seat.keys()
	seat_indexes.sort()
	for seat_index: Variant in seat_indexes:
		results.append(results_by_seat[seat_index])
	return results


func _normalize_final_events(raw_events: Variant) -> Array[Dictionary]:
	if not raw_events is Array:
		return []
	var latest_event: Dictionary = {}
	for raw_event: Variant in raw_events:
		raw_event = _dictionary_from_schema(raw_event)
		if not raw_event is Dictionary:
			continue
		var results := _normalize_final_results(raw_event.get("results", []))
		var winner_seat_indexes := _normalize_seat_indexes(
			raw_event.get("winnerSeatIndexes", [])
		)
		if results.is_empty() or winner_seat_indexes.is_empty():
			continue
		latest_event = {
			"type": "final_settlement",
			"results": results,
			"winner_seat_indexes": winner_seat_indexes,
		}
	if latest_event.is_empty():
		return []
	return [latest_event]


func _normalize_final_groups(raw_groups: Variant) -> Array:
	if not raw_groups is Array:
		return []
	if raw_groups.is_empty():
		return []
	if raw_groups.size() != 2:
		return []
	var groups: Array = []
	var selected_card_ids: Dictionary = {}
	for raw_group: Variant in raw_groups:
		if not raw_group is Array or raw_group.size() != 3:
			return []
		var group: Array[String] = []
		for raw_card_id: Variant in raw_group:
			if not raw_card_id is String:
				return []
			var card_id := str(raw_card_id)
			if card_id.is_empty() or selected_card_ids.has(card_id):
				return []
			selected_card_ids[card_id] = true
			group.append(card_id)
		groups.append(group)
	return groups


func _normalize_match_private_state(raw_state: Variant, room: Variant) -> Dictionary:
	raw_state = _dictionary_from_schema(raw_state)
	if not raw_state is Dictionary:
		return {}
	var participant_id := str(raw_state.get("participantId", ""))
	if participant_id.is_empty() or participant_id != str(room.get_session_id()):
		return {}
	var seat_index := int(raw_state.get("seatIndex", -1))
	if seat_index < 0 or seat_index >= ROOM_SEAT_COUNT:
		return {}
	var raw_hand: Variant = raw_state.get("hand", null)
	if not raw_hand is Array:
		return {}
	var claim_card_id: Variant = raw_state.get("claimCardId", null)
	if claim_card_id != null and not claim_card_id is String:
		return {}
	var hand: Array[Dictionary] = []
	var card_ids: Dictionary = {}
	for raw_card: Variant in raw_hand:
		var card := _normalize_card(raw_card)
		if card.is_empty() or card_ids.has(card["id"]):
			return {}
		card_ids[card["id"]] = true
		hand.append(card)
	return {
		"participant_id": participant_id,
		"seat_index": seat_index,
		"hand": hand,
		"claim_committed": bool(raw_state.get("claimCommitted", false)),
		"claim_card_id": claim_card_id,
		"final_committed": bool(raw_state.get("finalCommitted", false)),
		"final_groups": _normalize_final_groups(raw_state.get("finalGroups", [])),
	}


func _dictionary_from_schema(value: Variant) -> Variant:
	if value is Object and value.has_method("to_dictionary"):
		return value.to_dictionary()
	return value
