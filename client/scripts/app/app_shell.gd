extends Control
class_name AppShell

const AdapterScript = preload("res://scripts/network/colyseus_realtime_adapter.gd")
const MatchStoreScript = preload("res://scripts/match/match_store.gd")
const RoomStoreScript = preload("res://scripts/room/room_store.gd")
const LobbyScene = preload("res://scenes/lobby/lobby_screen.tscn")
const MatchScene = preload("res://scenes/match/match_screen.tscn")
const RoomScene = preload("res://scenes/room/room_screen.tscn")

var _adapter_override: Object
var _adapter: Object
var _match_store: Object
var _room_store: Object
var _lobby_screen: Variant
var _match_screen: Variant
var _room_screen: Variant
var _current_surface := ""


func set_realtime_adapter(adapter: Object) -> void:
	_adapter_override = adapter


func get_current_surface() -> String:
	return _current_surface


func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_adapter = _adapter_override if _adapter_override != null else AdapterScript.new()
	if _adapter is Node and _adapter.get_parent() == null:
		_adapter.name = "RealtimeAdapter"
		add_child(_adapter)

	_room_store = RoomStoreScript.new(_adapter)
	_room_store.left.connect(_on_game_room_left)
	_match_store = MatchStoreScript.new(_adapter)
	_match_store.match_activated.connect(_on_match_activated)

	_lobby_screen = LobbyScene.instantiate()
	_lobby_screen.set_realtime_adapter(_adapter)
	_lobby_screen.game_room_joined.connect(_on_game_room_joined)
	add_child(_lobby_screen)
	_current_surface = "lobby"


func _on_game_room_joined(_room_id: String) -> void:
	if _room_screen != null or _match_screen != null:
		return
	_lobby_screen.visible = false
	_room_screen = RoomScene.instantiate()
	_room_screen.set_room_store(_room_store)
	add_child(_room_screen)
	_current_surface = "room"


func _on_match_activated() -> void:
	if _match_screen != null:
		return
	_lobby_screen.visible = false
	if _room_screen != null:
		_room_screen.queue_free()
		_room_screen = null
	_match_screen = MatchScene.instantiate()
	_match_screen.set_match_store(_match_store)
	add_child(_match_screen)
	_current_surface = "match"


func _on_game_room_left(_code: int, _reason: String) -> void:
	if _room_screen != null:
		_room_screen.queue_free()
		_room_screen = null
	if _match_screen != null:
		_match_screen.queue_free()
		_match_screen = null
	_lobby_screen.visible = true
	_current_surface = "lobby"
