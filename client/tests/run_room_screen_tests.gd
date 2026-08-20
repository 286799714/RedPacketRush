extends SceneTree

const FakeRealtimeAdapter = preload("res://tests/fakes/fake_realtime_adapter.gd")
const RoomScreen = preload("res://scripts/room/room_screen.gd")
const RoomStore = preload("res://scripts/room/room_store.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_long_room_name_keeps_header_actions_visible()
	if _failures.is_empty():
		print("PASS: room screen layout tests")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_long_room_name_keeps_header_actions_visible() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var store := RoomStore.new(adapter)
	var screen := RoomScreen.new()
	screen.set_room_store(store)
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(960, 540)
	root.add_child(screen)
	await process_frame

	adapter.publish_game_room_state({
		"room_id": "room-long-name",
		"local_participant_id": "human-a",
		"status": "waiting",
		"display_name": "房".repeat(40),
		"deck_mode": "one",
		"action_deadline_seconds": 30,
		"host_participant_id": "human-a",
		"seats": [
			_seat(0, "human-a", "甲"),
			_seat(1, "human-b", "乙"),
			_seat(2, "human-c", "丙"),
			_seat(3, "human-d", "丁"),
		],
	})
	await process_frame

	var title_rect := screen._room_name_label.get_global_rect()
	var status_rect := screen._status_label.get_global_rect()
	var leave_rect := screen._leave_button.get_global_rect()
	var screen_rect := screen.get_global_rect()
	_expect_equal(screen._room_name_label.text.length(), 40, "测试应使用 40 字房名")
	_expect_equal(
		screen._room_name_label.text_overrun_behavior,
		TextServer.OVERRUN_TRIM_ELLIPSIS,
		"房名应启用省略"
	)
	_expect(title_rect.size.x > 0.0, "房名仍应保留可见宽度")
	_expect(status_rect.position.x >= screen_rect.position.x, "状态标签不应被推出左侧")
	_expect(leave_rect.position.x >= status_rect.end.x, "离开按钮不应与状态标签重叠")
	_expect(leave_rect.end.x <= screen_rect.end.x, "离开按钮不应被推出右侧")
	_expect(title_rect.end.x <= status_rect.position.x, "省略后的房名不应覆盖状态标签")
	screen.queue_free()
	await process_frame


func _seat(seat_index: int, participant_id: String, nickname: String) -> Dictionary:
	return {
		"seat_index": seat_index,
		"participant_id": participant_id,
		"nickname": nickname,
		"is_bot": false,
		"is_ready": true,
	}


func _expect(condition: bool, context: String) -> void:
	if not condition:
		_failures.append(context)


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
