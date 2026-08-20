extends RefCounted
class_name RoomSettings

var display_name: String
var deck_mode: String
var action_deadline_seconds: int


func _init(
	initial_display_name: String,
	initial_deck_mode: String,
	initial_action_deadline_seconds: int
) -> void:
	display_name = initial_display_name
	deck_mode = initial_deck_mode
	action_deadline_seconds = initial_action_deadline_seconds
