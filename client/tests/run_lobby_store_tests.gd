extends SceneTree

const FakeRealtimeAdapter = preload("res://tests/fakes/fake_realtime_adapter.gd")
const LobbyStore = preload("res://scripts/lobby/lobby_store.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_connection_state_is_exposed_in_simplified_chinese()
	_test_room_add_change_and_remove_are_applied_in_realtime()

	if _failures.is_empty():
		print("PASS: lobby store tests")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_connection_state_is_exposed_in_simplified_chinese() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var lobby := LobbyStore.new(adapter)

	adapter.publish_connection_state("connecting")
	_expect_equal(lobby.connection_status_text, "正在连接服务器...", "连接中状态")
	adapter.publish_connection_state("connected")
	_expect_equal(lobby.connection_status_text, "已连接", "已连接状态")
	adapter.publish_connection_state("retryable_error", "服务器暂时不可用")
	_expect_equal(lobby.connection_status_text, "连接失败，可重试：服务器暂时不可用", "可重试错误状态")
	adapter.publish_connection_state("disconnected")
	_expect_equal(lobby.connection_status_text, "未连接", "断开状态")


func _test_room_add_change_and_remove_are_applied_in_realtime() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var lobby := LobbyStore.new(adapter)
	if not lobby.has_method("get_rooms"):
		_failures.append("大厅状态必须公开 get_rooms()")
		return

	adapter.publish_rooms([
		{"room_id": "room-a", "name": "午休局", "participant_count": 1, "seat_capacity": 4, "deck_mode": 1},
		{"room_id": "room-b", "name": "双牌局", "participant_count": 2, "seat_capacity": 4, "deck_mode": 2},
	])
	_expect_equal(lobby.get_rooms().size(), 2, "房间新增")
	_expect_equal(lobby.get_rooms()[0]["name"], "午休局", "房间名称")

	adapter.publish_rooms([
		{"room_id": "room-a", "name": "午休局", "participant_count": 3, "seat_capacity": 4, "deck_mode": 1},
		{"room_id": "room-b", "name": "双牌局", "participant_count": 2, "seat_capacity": 4, "deck_mode": 2},
	])
	_expect_equal(lobby.get_rooms()[0]["participant_count"], 3, "房间元数据变更")

	adapter.publish_rooms([
		{"room_id": "room-b", "name": "双牌局", "participant_count": 2, "seat_capacity": 4, "deck_mode": 2},
	])
	_expect_equal(lobby.get_rooms().size(), 1, "房间移除")
	_expect_equal(lobby.get_rooms()[0]["room_id"], "room-b", "移除后保留正确房间")


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
