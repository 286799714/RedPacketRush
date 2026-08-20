extends RefCounted

signal connection_state_changed(state: String, detail: String)
signal lobby_rooms_changed(rooms: Array[Dictionary])

var connection_requests: Array[Dictionary] = []


func connect_lobby(endpoint: String, nickname: String) -> void:
	connection_requests.append({"endpoint": endpoint, "nickname": nickname})


func publish_connection_state(state: String, detail: String = "") -> void:
	connection_state_changed.emit(state, detail)


func publish_rooms(rooms: Array[Dictionary]) -> void:
	lobby_rooms_changed.emit(rooms)
