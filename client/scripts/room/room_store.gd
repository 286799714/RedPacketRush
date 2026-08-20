extends RefCounted
class_name RoomStore

signal state_changed()
signal action_failed(code: String, message: String)
signal left(code: int, reason: String)

var room_id := ""
var local_participant_id := ""
var status := ""
var display_name := ""
var deck_mode := "one"
var action_deadline_seconds := 30
var host_participant_id := ""

var _adapter: Object
var _seats: Array[Dictionary] = []


func _init(adapter: Object) -> void:
	_adapter = adapter
	_adapter.game_room_state_changed.connect(_on_game_room_state_changed)
	_adapter.room_action_failed.connect(
		func(code: String, message: String): action_failed.emit(code, message)
	)
	_adapter.game_room_left.connect(_on_game_room_left)


func get_seats() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for seat in _seats:
		result.append(seat.duplicate(true))
	return result


func is_local_host() -> bool:
	return not local_participant_id.is_empty() and local_participant_id == host_participant_id


func is_local_ready() -> bool:
	for seat in _seats:
		if str(seat.get("participant_id", "")) == local_participant_id:
			return bool(seat.get("is_ready", false))
	return false


func can_configure() -> bool:
	return status == "waiting" and is_local_host()


func can_fill_bots() -> bool:
	if not can_configure():
		return false
	return _seats.any(func(seat: Dictionary): return str(seat.get("participant_id", "")).is_empty())


func can_toggle_ready() -> bool:
	if status != "waiting":
		return false
	for seat in _seats:
		if str(seat.get("participant_id", "")) == local_participant_id:
			return not bool(seat.get("is_bot", false))
	return false


func can_start() -> bool:
	if status != "waiting" or not is_local_host() or _seats.size() != 4:
		return false
	for seat in _seats:
		if str(seat.get("participant_id", "")).is_empty() or not bool(seat.get("is_ready", false)):
			return false
	return true


func set_ready(ready: bool) -> void:
	_adapter.set_ready(ready)


func configure_room(configuration: Object) -> void:
	_adapter.configure_room(configuration)


func fill_bots() -> void:
	_adapter.fill_bots()


func start_match() -> void:
	_adapter.start_match()


func leave_room() -> void:
	_adapter.leave_game_room()


func _on_game_room_state_changed(snapshot: Dictionary) -> void:
	room_id = str(snapshot.get("room_id", ""))
	local_participant_id = str(snapshot.get("local_participant_id", ""))
	status = str(snapshot.get("status", ""))
	display_name = str(snapshot.get("display_name", ""))
	deck_mode = str(snapshot.get("deck_mode", "one"))
	action_deadline_seconds = int(snapshot.get("action_deadline_seconds", 30))
	host_participant_id = str(snapshot.get("host_participant_id", ""))
	_seats.clear()
	var raw_seats: Variant = snapshot.get("seats", [])
	if raw_seats is Array:
		for raw_seat: Variant in raw_seats:
			if raw_seat is Dictionary:
				_seats.append(raw_seat.duplicate(true))
	state_changed.emit()


func _on_game_room_left(code: int, reason: String) -> void:
	room_id = ""
	local_participant_id = ""
	status = ""
	display_name = ""
	deck_mode = "one"
	action_deadline_seconds = 30
	host_participant_id = ""
	_seats.clear()
	state_changed.emit()
	left.emit(code, reason)
