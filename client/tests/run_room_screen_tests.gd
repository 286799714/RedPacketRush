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

	var long_name := "房".repeat(40)
	var room_name_label := _find_visible_label_exact(screen, long_name)
	var status_label := _find_visible_label_exact(screen, "等待准备")
	var leave_button := _find_visible_button(screen, "离开房间")
	_expect(room_name_label != null and status_label != null and leave_button != null, "房间标题、状态和离开命令可见")
	if room_name_label == null or status_label == null or leave_button == null:
		await _unmount_room_screen(fixture)
		return
	var title_rect := room_name_label.get_global_rect()
	var status_rect := status_label.get_global_rect()
	var leave_rect := leave_button.get_global_rect()
	var screen_rect := screen.get_global_rect()
	_expect_equal(room_name_label.text.length(), 40, "测试应使用 40 字房名")
	_expect_equal(
		room_name_label.text_overrun_behavior,
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
	var seat_panels := _find_seat_panels(screen)
	var deck_mode_option := _find_option_button_with_item(screen, "两副牌")
	var deadline_option := _find_option_button_with_item(screen, "60 秒")
	var start_button := _find_visible_button(screen, "开始对局")
	_expect_equal(seat_panels.size(), 4, "房间固定四席")
	_expect(deck_mode_option != null and deck_mode_option.get_item_text(deck_mode_option.selected) == "两副牌", "房间设置显示双副牌")
	_expect(deadline_option != null and deadline_option.get_item_text(deadline_option.selected) == "30 秒", "房间设置显示 30 秒限时")
	_expect(start_button != null and not start_button.disabled, "房主提供可用的开始命令")
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
	var start_button := _find_visible_button(screen, "开始对局")
	var long_nickname := str(seats[0]["nickname"])
	var name_labels := _find_visible_labels_exact(screen, long_nickname)
	_expect(start_button != null, "开始命令可见")
	_expect_equal(name_labels.size(), 4, "四个超长昵称均呈现")
	if start_button == null:
		await _unmount_room_screen(fixture)
		return
	var start_rect: Rect2 = start_button.get_global_rect()
	for name_label in name_labels:
		_expect(name_label.text_overrun_behavior == TextServer.OVERRUN_TRIM_ELLIPSIS, "超长昵称启用省略")
		var name_rect: Rect2 = name_label.get_global_rect()
		_expect(name_rect.size.x > 0.0 and name_rect.end.x <= 960.0, "超长昵称仍在席位内")
	adapter.publish_room_error("invalid_configuration", "房间设置已锁定")
	await process_frame
	_expect(_find_visible_label_exact(screen, "房间设置已锁定") != null, "房间错误反馈可见")
	_expect_equal(start_button.get_global_rect(), start_rect, "错误反馈不推动开始按钮")
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
	var seat_panels := _find_seat_panels(screen)
	_expect_equal(seat_panels.size(), 4, "%s 四个席位区域可见" % label)
	for panel in seat_panels:
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


func _find_seat_panels(root_node: Node) -> Array[PanelContainer]:
	var result: Array[PanelContainer] = []
	for seat_number in range(1, 5):
		var heading := _find_visible_label_exact(root_node, "席位 %d" % seat_number)
		var ancestor := heading.get_parent() if heading != null else null
		while ancestor != null and ancestor != root_node:
			if ancestor is PanelContainer:
				result.append(ancestor)
				break
			ancestor = ancestor.get_parent()
	return result


func _find_option_button_with_item(root_node: Node, item_text: String) -> OptionButton:
	for node in root_node.find_children("*", "OptionButton", true, false):
		if node is not OptionButton or not node.is_visible_in_tree():
			continue
		for item_index in range(node.item_count):
			if node.get_item_text(item_index) == item_text:
				return node
	return null


func _find_visible_button(root_node: Node, expected_text: String) -> Button:
	for node in root_node.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and node.text == expected_text:
			return node
	return null


func _find_visible_label_exact(root_node: Node, expected_text: String) -> Label:
	for node in root_node.find_children("*", "Label", true, false):
		if node is Label and node.is_visible_in_tree() and node.text == expected_text:
			return node
	return null


func _find_visible_labels_exact(root_node: Node, expected_text: String) -> Array[Label]:
	var result: Array[Label] = []
	for node in root_node.find_children("*", "Label", true, false):
		if node is Label and node.is_visible_in_tree() and node.text == expected_text:
			result.append(node)
	return result


func _expect(condition: bool, context: String) -> void:
	if not condition:
		_failures.append(context)


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
