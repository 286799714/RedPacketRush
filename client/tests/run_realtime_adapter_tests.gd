extends SceneTree

const Adapter = preload("res://scripts/network/colyseus_realtime_adapter.gd")
const FakeColyseusClient = preload("res://tests/fakes/fake_colyseus_client.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_failed_join_is_disposed()
	_test_failed_retry_preserves_active_room()
	_test_new_attempt_detaches_old_pending_room()
	_test_null_retry_preserves_active_room()

	if _failures.is_empty():
		print("PASS: realtime adapter lifecycle tests")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_failed_join_is_disposed() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed_failures: Array[String] = []
	var joined_ids: Array[String] = []
	adapter.game_room_failed.connect(func(message: String): observed_failures.append(message))
	adapter.game_room_joined.connect(func(room_id: String): joined_ids.append(room_id))
	var stale_room := client.queue_join_room("locked-room")

	adapter.join_game_room("locked-room", "甲")
	stale_room.emit_error(421, "房间已锁定")

	_expect_equal(joined_ids, [], "失败加入不应通知 joined")
	_expect_equal(stale_room.leave_count, 1, "失败 wrapper 应被 leave")
	_expect_equal(stale_room.connection_count(&"error"), 0, "失败 wrapper 的回调应断开")
	_expect_equal(observed_failures, ["房间已锁定"], "失败加入错误应只通知一次")
	adapter.queue_free()


func _test_failed_retry_preserves_active_room() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed := {"state_count": 0, "leave_count": 0}
	adapter.game_room_state_changed.connect(func(_state: Dictionary): observed["state_count"] += 1)
	adapter.game_room_left.connect(func(_code: int, _reason: String): observed["leave_count"] += 1)

	var active_room := client.queue_join_room("active-room")
	adapter.join_game_room("active-room", "甲")
	active_room.emit_joined()
	var stale_room := client.queue_join_room("full-room")
	adapter.join_game_room("full-room", "甲")
	stale_room.emit_error(421, "房间已满")

	_expect_equal(stale_room.leave_count, 1, "失败重试 wrapper 应被 leave")
	_expect_equal(stale_room.connection_count(&"joined"), 0, "失败重试 wrapper 的回调应断开")
	adapter.set_ready(true)
	_expect_equal(
		active_room.sent_messages,
		[{"type": "set_ready", "data": {"ready": true}}],
		"失败重试后意图仍应路由到当前 active 房间"
	)
	active_room.emit_state({"status": "waiting"})
	stale_room.emit_state({"status": "started"})
	stale_room.emit_left(1000, "过期")
	_expect_equal(observed["state_count"], 1, "旧 wrapper 回调不应污染 active 状态")
	_expect_equal(observed["leave_count"], 0, "旧 wrapper 离开不应清理 active 房间")
	adapter.queue_free()


func _test_new_attempt_detaches_old_pending_room() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var joined_ids: Array[String] = []
	adapter.game_room_joined.connect(func(room_id: String): joined_ids.append(room_id))

	var first_pending := client.queue_join_room("first-pending")
	adapter.join_game_room("first-pending", "甲")
	var second_pending := client.queue_join_room("second-pending")
	adapter.join_game_room("second-pending", "甲")

	_expect_equal(first_pending.leave_count, 1, "新尝试应清理旧 pending wrapper")
	_expect_equal(first_pending.connection_count(&"joined"), 0, "旧 pending 回调应断开")
	first_pending.emit_joined()
	second_pending.emit_joined()
	_expect_equal(joined_ids, ["second-pending"], "只应通知新尝试的 joined")
	adapter.set_ready(true)
	_expect_equal(
		second_pending.sent_messages,
		[{"type": "set_ready", "data": {"ready": true}}],
		"新尝试成功后意图应路由到新 active 房间"
	)
	adapter.queue_free()


func _test_null_retry_preserves_active_room() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var failures: Array[String] = []
	adapter.game_room_failed.connect(func(message: String): failures.append(message))

	var active_room := client.queue_join_room("active-room")
	adapter.join_game_room("active-room", "甲")
	active_room.emit_joined()
	var pending_room := client.queue_join_room("pending-room")
	adapter.join_game_room("pending-room", "甲")
	client.queue_null_join()
	adapter.join_game_room("stale-room", "甲")

	_expect_equal(pending_room.leave_count, 1, "空请求结果应 leave 旧 pending wrapper")
	_expect_equal(pending_room.connection_count(&"joined"), 0, "空请求结果应断开旧 pending 回调")
	_expect_equal(failures, ["房间请求未能发出"], "空请求结果应返回明确失败")
	adapter.set_ready(true)
	_expect_equal(
		active_room.sent_messages,
		[{"type": "set_ready", "data": {"ready": true}}],
		"空请求结果不应覆盖当前 active 房间"
	)
	adapter.queue_free()


func _new_adapter() -> Adapter:
	var adapter := Adapter.new()
	root.add_child(adapter)
	adapter._connected = true
	return adapter


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
