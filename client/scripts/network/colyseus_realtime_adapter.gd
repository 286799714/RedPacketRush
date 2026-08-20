extends Node
class_name ColyseusRealtimeAdapter

signal connection_state_changed(state: String, detail: String)
signal lobby_rooms_changed(rooms: Array[Dictionary])
signal game_room_joined(room_id: String)
signal game_room_failed(message: String)
signal game_room_state_changed(state: Dictionary)
signal game_room_left(code: int, reason: String)
signal game_room_connection_changed(state: String, detail: String)
signal room_action_failed(code: String, message: String)

const ColyseusSdk = preload("res://addons/colyseus/colyseus.gd")
const GameSchema = preload("res://schema/schema.gd")
const LOBBY_ROOM_TYPE := "lobby"
const GAME_ROOM_TYPE := "game"
const ROOM_SEAT_COUNT := 4

var _client: Variant
var _lobby_room: Variant
var _game_room: Variant
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
	_game_room = null
	if previous_room != null:
		previous_room.leave()
	if announce:
		game_room_left.emit(1000, "")


func create_game_room(
	settings: RoomSettings,
	nickname: String
) -> void:
	if not _connected or _client == null:
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
		game_room_failed.emit("请先连接服务器")
		return
	_watch_game_room(_client.join_by_id(room_id, {"nickname": nickname}))


func set_ready(ready: bool) -> void:
	_send_game_room_message("set_ready", {"ready": ready})


func configure_room(deck_mode: String, deadline_seconds: int) -> void:
	_send_game_room_message("configure", {
		"deckMode": deck_mode,
		"actionDeadlineSeconds": deadline_seconds,
	})


func fill_bots() -> void:
	_send_game_room_message("fill_bots")


func start_match() -> void:
	_send_game_room_message("start")


func _exit_tree() -> void:
	disconnect_game_room()
	disconnect_lobby(false)


func _watch_game_room(room: Variant) -> void:
	if room == null:
		game_room_failed.emit("房间请求未能发出")
		return
	_game_room = room
	room.set_state_type(GameSchema.GameRoomState)
	room.joined.connect(_on_game_room_joined.bind(room))
	room.state_changed.connect(_on_game_room_state_changed.bind(room))
	room.message_received.connect(_on_game_room_message.bind(room))
	room.error.connect(_on_game_room_error.bind(room))
	room.left.connect(_on_game_room_left.bind(room))
	room.dropped.connect(_on_game_room_dropped.bind(room))
	room.reconnected.connect(_on_game_room_reconnected.bind(room))


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
	if room == _game_room:
		game_room_joined.emit(room.get_id())
		game_room_connection_changed.emit("connected", "")


func _on_game_room_error(_code: int, message: String, room: Variant) -> void:
	if room == _game_room:
		game_room_failed.emit(message)


func _on_game_room_state_changed(room: Variant) -> void:
	if room != _game_room:
		return
	var snapshot := _normalize_game_room_state(room.get_state(), room)
	if not snapshot.is_empty():
		game_room_state_changed.emit(snapshot)


func _on_game_room_message(type: Variant, data: Variant, room: Variant) -> void:
	if room != _game_room or str(type) != "room_error":
		return
	if not data is Dictionary:
		room_action_failed.emit("unknown", str(data))
		return
	room_action_failed.emit(
		str(data.get("code", "unknown")),
		str(data.get("message", "房间操作失败"))
	)


func _on_game_room_left(code: int, reason: String, room: Variant) -> void:
	if room != _game_room:
		return
	_game_room = null
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
				}
	var seats: Array[Dictionary] = []
	for seat_index in range(ROOM_SEAT_COUNT):
		seats.append(seats_by_index.get(seat_index, {
			"seat_index": seat_index,
			"participant_id": "",
			"nickname": "",
			"is_bot": false,
			"is_ready": false,
		}))

	return {
		"room_id": room.get_id(),
		"local_participant_id": room.get_session_id(),
		"status": str(raw_state.get("status", "")),
		"display_name": str(raw_state.get("displayName", "")),
		"deck_mode": str(raw_state.get("deckMode", "one")),
		"action_deadline_seconds": int(raw_state.get("actionDeadlineSeconds", 30)),
		"host_participant_id": str(raw_state.get("hostParticipantId", "")),
		"seats": seats,
	}
