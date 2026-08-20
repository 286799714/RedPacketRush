extends RefCounted
class_name RoomConfiguration

var deck_mode: String
var action_deadline_seconds: int


func _init(initial_deck_mode: String, initial_action_deadline_seconds: int) -> void:
	deck_mode = initial_deck_mode
	action_deadline_seconds = initial_action_deadline_seconds
