extends Node
class_name ColyseusRealtimeAdapter

signal connection_state_changed(state: String, detail: String)
signal lobby_rooms_changed(rooms: Array[Dictionary])
signal game_room_joined(room_id: String)
signal game_room_failed(message: String)

const ColyseusSdk = preload("res://addons/colyseus/colyseus.gd")
const LOBBY_ROOM_TYPE := "lobby"
const GAME_ROOM_TYPE := "game"

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
	var previous_room: Variant = _game_room
	_game_room = null
	if previous_room != null:
		previous_room.leave()


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


func _exit_tree() -> void:
	disconnect_game_room()
	disconnect_lobby(false)


func _watch_game_room(room: Variant) -> void:
	if room == null:
		game_room_failed.emit("房间请求未能发出")
		return
	_game_room = room
	room.joined.connect(_on_game_room_joined.bind(room))
	room.error.connect(_on_game_room_error.bind(room))


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
	var participant_count := int(_read(raw_room, "clients", "clients", 0))
	var seat_capacity := int(_read(raw_room, "maxClients", "max_clients", 4))
	var locked := bool(_read(raw_room, "locked", "locked", false))
	var is_private := bool(_read(raw_room, "private", "private", false))
	var metadata: Variant = _read(raw_room, "metadata", "metadata", {})
	if metadata is String:
		metadata = JSON.parse_string(metadata)
	if not metadata is Dictionary:
		metadata = {}
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


func _on_game_room_error(_code: int, message: String, room: Variant) -> void:
	if room == _game_room:
		game_room_failed.emit(message)
