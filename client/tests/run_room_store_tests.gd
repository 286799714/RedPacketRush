extends SceneTree

const FakeRealtimeAdapter = preload("res://tests/fakes/fake_realtime_adapter.gd")
const RoomConfiguration = preload("res://scripts/domain/room_configuration.gd")
const RoomStore = preload("res://scripts/room/room_store.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_public_snapshot_derives_local_room_capabilities()
	_test_room_intentions_are_forwarded_without_optimistic_state()
	_test_targeted_error_and_leave_are_exposed_without_stale_state()

	if _failures.is_empty():
		print("PASS: room store tests")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_public_snapshot_derives_local_room_capabilities() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var room := RoomStore.new(adapter)
	adapter.publish_game_room_state({
		"room_id": "room-a",
		"local_participant_id": "human-a",
		"status": "waiting",
		"display_name": "周四牌局",
		"deck_mode": "two",
		"action_deadline_seconds": 60,
		"host_participant_id": "human-a",
		"seats": [
			_seat(0, "human-a", "甲", false, false),
			_seat(1, "human-b", "乙", false, true),
			_seat(2, "bot-c", "机器人 3", true, true),
			_seat(3, "", "", false, false),
		],
	})

	_expect_equal(room.display_name, "周四牌局", "房间名称")
	_expect_equal(room.deck_mode, "two", "牌组设置")
	_expect_equal(room.action_deadline_seconds, 60, "行动时限")
	_expect_equal(room.get_seats().size(), 4, "固定四席")
	_expect_equal(room.is_local_host(), true, "本地房主")
	_expect_equal(room.is_local_ready(), false, "本地准备状态")
	_expect_equal(room.can_configure(), true, "房主可配置")
	_expect_equal(room.can_fill_bots(), true, "有空座可填机器人")
	_expect_equal(room.can_toggle_ready(), true, "人类可切换准备")
	_expect_equal(room.can_start(), false, "未满座不能开始")


func _test_room_intentions_are_forwarded_without_optimistic_state() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var room := RoomStore.new(adapter)
	adapter.publish_game_room_state({
		"room_id": "room-a",
		"local_participant_id": "human-a",
		"status": "waiting",
		"display_name": "意图测试",
		"deck_mode": "one",
		"action_deadline_seconds": 30,
		"host_participant_id": "human-a",
		"seats": [
			_seat(0, "human-a", "甲", false, false),
			_seat(1, "", "", false, false),
			_seat(2, "", "", false, false),
			_seat(3, "", "", false, false),
		],
	})

	room.set_ready(true)
	room.configure_room(RoomConfiguration.new("two", 60))
	room.fill_bots()
	room.start_match()
	room.leave_room()

	_expect_equal(adapter.room_requests, [
		{"type": "set_ready", "payload": {"ready": true}},
		{"type": "configure", "payload": {"deckMode": "two", "actionDeadlineSeconds": 60}},
		{"type": "fill_bots", "payload": null},
		{"type": "start", "payload": null},
	], "房间意图")
	_expect_equal(adapter.leave_game_room_requests, 1, "离开意图")
	_expect_equal(room.deck_mode, "one", "设置等待服务器确认")
	_expect_equal(room.is_local_ready(), false, "准备等待服务器确认")


func _test_targeted_error_and_leave_are_exposed_without_stale_state() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var room := RoomStore.new(adapter)
	var observed := {"error": {}, "leave_count": 0}
	room.action_failed.connect(func(code: String, message: String):
		observed["error"] = {"code": code, "message": message}
	)
	room.left.connect(func(_code: int, _reason: String): observed["leave_count"] += 1)
	adapter.publish_game_room_state({
		"room_id": "room-a",
		"local_participant_id": "human-a",
		"status": "waiting",
		"display_name": "生命周期测试",
		"deck_mode": "one",
		"action_deadline_seconds": 30,
		"host_participant_id": "human-a",
		"seats": [
			_seat(0, "human-a", "甲", false, false),
			_seat(1, "", "", false, false),
			_seat(2, "", "", false, false),
			_seat(3, "", "", false, false),
		],
	})

	adapter.publish_room_error("host_only", "只有房主可以执行此操作")
	_expect_equal(observed["error"], {
		"code": "host_only",
		"message": "只有房主可以执行此操作",
	}, "定向错误")
	adapter.publish_game_room_left(1000, "")
	_expect_equal(observed["leave_count"], 1, "离开信号")
	_expect_equal(room.room_id, "", "离开清空房间")
	_expect_equal(room.get_seats().size(), 0, "离开清空座位")
	_expect_equal(room.can_configure(), false, "离开清空能力")


func _seat(
	seat_index: int,
	participant_id: String,
	nickname: String,
	is_bot: bool,
	is_ready: bool
) -> Dictionary:
	return {
		"seat_index": seat_index,
		"participant_id": participant_id,
		"nickname": nickname,
		"is_bot": is_bot,
		"is_ready": is_ready,
	}


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
