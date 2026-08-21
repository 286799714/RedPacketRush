extends RefCounted
class_name FakeColyseusClient


class FakeRoom extends RefCounted:
	signal joined()
	signal state_changed()
	signal message_received(type: Variant, data: Variant)
	signal error(code: int, message: String)
	signal left(code: int, reason: String)
	signal dropped(code: int, reason: String)
	signal reconnected()

	var room_id := ""
	var session_id := "session-a"
	var leave_count := 0
	var sent_messages: Array[Dictionary] = []
	var reconnection_options: Array[Dictionary] = []
	var state: Variant = {}
	var state_type: Variant

	func _init(id: String) -> void:
		room_id = id

	func set_state_type(value: Variant) -> void:
		state_type = value

	func get_id() -> String:
		return room_id

	func get_session_id() -> String:
		return session_id

	func get_state() -> Variant:
		return state

	func send_message(type: Variant, data: Variant = null) -> void:
		sent_messages.append({"type": type, "data": data})

	func set_reconnection_options(options: Dictionary) -> void:
		reconnection_options.append(options.duplicate(true))

	func leave() -> void:
		leave_count += 1

	func emit_joined() -> void:
		joined.emit()

	func emit_state(next_state: Variant = {}) -> void:
		state = next_state
		state_changed.emit()

	func emit_error(code: int, message: String) -> void:
		error.emit(code, message)

	func emit_left(code: int = 1000, reason: String = "") -> void:
		left.emit(code, reason)

	func emit_dropped(code: int = 1006, reason: String = "") -> void:
		dropped.emit(code, reason)

	func emit_reconnected() -> void:
		reconnected.emit()

	func connection_count(signal_name: StringName) -> int:
		return get_signal_connection_list(signal_name).size()


var _queued_rooms: Array[Variant] = []
var last_room: Variant


func queue_join_room(room_id: String) -> FakeRoom:
	var room := FakeRoom.new(room_id)
	_queued_rooms.append(room)
	return room


func queue_null_join() -> void:
	_queued_rooms.append(null)


func join_by_id(_room_id: String, _options: Dictionary = {}) -> Variant:
	if _queued_rooms.is_empty():
		last_room = null
		return null
	last_room = _queued_rooms.pop_front()
	return last_room


func create(_room_name: String, _options: Dictionary = {}) -> Variant:
	return join_by_id("created")
