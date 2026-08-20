extends RefCounted
class_name LobbyStore

signal connection_changed(state: String, status_text: String)
signal rooms_changed(rooms: Array[Dictionary])
signal game_room_joined(room_id: String)
signal action_failed(message: String)

const STATUS_TEXT := {
	"connecting": "正在连接服务器...",
	"connected": "已连接",
	"retryable_error": "连接失败，可重试",
	"disconnected": "未连接",
}

var connection_state := "disconnected"
var connection_status_text := "未连接"

var _adapter: Object
var _rooms: Array[Dictionary] = []


func _init(adapter: Object) -> void:
	_adapter = adapter
	_adapter.connection_state_changed.connect(_on_connection_state_changed)
	_adapter.lobby_rooms_changed.connect(_on_lobby_rooms_changed)
	if _adapter.has_signal("game_room_joined"):
		_adapter.game_room_joined.connect(func(room_id: String): game_room_joined.emit(room_id))
	if _adapter.has_signal("game_room_failed"):
		_adapter.game_room_failed.connect(func(message: String): action_failed.emit(message))


func connect_lobby(endpoint: String, nickname: String) -> void:
	_adapter.connect_lobby(endpoint, nickname)


func create_game_room(
	settings: RoomSettings,
	nickname: String
) -> void:
	_adapter.create_game_room(settings, nickname)


func join_game_room(room_id: String, nickname: String) -> void:
	_adapter.join_game_room(room_id, nickname)


func get_rooms() -> Array[Dictionary]:
	return _rooms


func _on_connection_state_changed(state: String, detail: String) -> void:
	connection_state = state
	connection_status_text = STATUS_TEXT.get(state, "未知连接状态")
	if state == "retryable_error" and not detail.is_empty():
		connection_status_text += "：%s" % detail
	connection_changed.emit(connection_state, connection_status_text)


func _on_lobby_rooms_changed(rooms: Array[Dictionary]) -> void:
	_rooms.clear()
	for room in rooms:
		_rooms.append(room.duplicate(true))
	rooms_changed.emit(_rooms)
