extends SceneTree

const FakeRealtimeAdapter = preload("res://tests/fakes/fake_realtime_adapter.gd")
const RoomScreen = preload("res://scripts/room/room_screen.gd")
const RoomStore = preload("res://scripts/room/room_store.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_long_room_name_keeps_header_actions_visible()
	await _test_four_seats_and_host_controls_fit_at_two_sizes()
	await _test_long_nicknames_and_errors_do_not_shift_controls()
	if _failures.is_empty():
		print("PASS: room screen layout tests")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _mount_room_screen(viewport_size := Vector2(960, 540)) -> Dictionary:
	var adapter := FakeRealtimeAdapter.new()
	var store := RoomStore.new(adapter)
	var screen := RoomScreen.new()
	screen.set_room_store(store)
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = viewport_size
	root.add_child(screen)
	await process_frame
	return {"adapter": adapter, "screen": screen}


func _unmount_room_screen(fixture: Dictionary) -> void:
	var screen: RoomScreen = fixture["screen"]
	screen.queue_free()
	await process_frame


func _test_long_room_name_keeps_header_actions_visible() -> void:
	var fixture := await _mount_room_screen()
	var adapter: Object = fixture["adapter"]
	var screen: RoomScreen = fixture["screen"]

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
	await _unmount_room_screen(fixture)


func _seat(seat_index: int, participant_id: String, nickname: String) -> Dictionary:
	return {
		"seat_index": seat_index,
		"participant_id": participant_id,
		"nickname": nickname,
		"is_bot": false,
		"is_ready": true,
	}


func _test_four_seats_and_host_controls_fit_at_two_sizes() -> void:
	var fixture := await _mount_room_screen()
	var adapter: Object = fixture["adapter"]
	var screen: RoomScreen = fixture["screen"]
	adapter.publish_game_room_state(_room_snapshot("双副牌测试局", "waiting", "human-a", "two", _seats()))
	await process_frame
	_expect_equal(screen._seat_panels.size(), 4, "房间固定四席")
	_expect(screen._deck_mode_option.name != "", "房间设置提供牌组选项")
	_expect(screen._deadline_option.name != "", "房间设置提供限时选项")
	_expect(screen._start_button.name != "", "房主提供开始按钮")
	_assert_room_regions_fit(screen, Vector2(960, 540), "960x540")
	screen.size = Vector2(1280, 720)
	await process_frame
	_assert_room_regions_fit(screen, Vector2(1280, 720), "1280x720")
	await _unmount_room_screen(fixture)


func _test_long_nicknames_and_errors_do_not_shift_controls() -> void:
	var fixture := await _mount_room_screen()
	var adapter: Object = fixture["adapter"]
	var screen: RoomScreen = fixture["screen"]
	var seats := _seats()
	for index in range(seats.size()):
		seats[index]["nickname"] = "参与者-%s" % "很长的昵称".repeat(8)
	adapter.publish_game_room_state(_room_snapshot("房间", "waiting", "human-a", "one", seats))
	await process_frame
	var start_rect: Rect2 = screen._start_button.get_global_rect()
	for name_label in screen._seat_name_labels:
		_expect(name_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "超长昵称启用省略")
		var name_rect: Rect2 = name_label.get_global_rect()
		_expect(name_rect.size.x > 0.0 and name_rect.end.x <= 960.0, "超长昵称仍在席位内")
	adapter.publish_room_error("invalid_configuration", "房间设置已锁定")
	await process_frame
	_expect_equal(screen._feedback_label.text, "房间设置已锁定", "房间错误反馈可见")
	_expect_equal(screen._start_button.get_global_rect(), start_rect, "错误反馈不推动开始按钮")
	await _unmount_room_screen(fixture)


func _room_snapshot(
	display_name: String,
	status: String,
	host_id: String,
	deck_mode: String,
	seats: Array[Dictionary]
) -> Dictionary:
	return {
		"room_id": "room-test",
		"local_participant_id": "human-a",
		"status": status,
		"display_name": display_name,
		"deck_mode": deck_mode,
		"action_deadline_seconds": 30,
		"host_participant_id": host_id,
		"seats": seats,
	}


func _seats() -> Array[Dictionary]:
	return [
		_seat(0, "human-a", "甲"),
		_seat(1, "human-b", "乙"),
		_seat(2, "human-c", "丙"),
		_seat(3, "human-d", "丁"),
	]


func _assert_room_regions_fit(screen: RoomScreen, viewport_size: Vector2, label: String) -> void:
	for panel in screen._seat_panels:
		var rect: Rect2 = panel.get_global_rect()
		_expect(rect.size.x >= 180.0 and rect.size.y >= 100.0, "%s 席位尺寸稳定" % label)
		_expect(rect.position.x >= 0.0 and rect.position.y >= 0.0, "%s 席位不越出左上边界" % label)
		_expect(rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y, "%s 席位不越出视口" % label)
	var controls := screen.find_child("RoomControlsPanel", true, false)
	var workspace := screen.find_child("RoomWorkspace", true, false)
	_expect(controls != null and workspace != null, "%s 房间主区域节点稳定" % label)
	if controls != null:
		var controls_rect: Rect2 = controls.get_global_rect()
		_expect(controls_rect.end.x <= viewport_size.x and controls_rect.end.y <= viewport_size.y, "%s 设置区不越界" % label)
	if workspace != null:
		var workspace_rect: Rect2 = workspace.get_global_rect()
		_expect(workspace_rect.end.x <= viewport_size.x and workspace_rect.end.y <= viewport_size.y, "%s 工作区不越界" % label)


func _expect(condition: bool, context: String) -> void:
	if not condition:
		_failures.append(context)


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
