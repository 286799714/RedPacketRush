extends SceneTree

const FakeRealtimeAdapter = preload("res://tests/fakes/fake_realtime_adapter.gd")
const LobbyScreen = preload("res://scripts/lobby/lobby_screen.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	await _test_loading_state_is_distinct_from_empty_state()
	await _test_empty_state_and_key_regions_fit_at_two_sizes()
	await _test_validation_feedback_is_visible_without_moving_controls()
	await _test_retry_state_exposes_retry_action()
	await _test_populated_selection_is_readable_at_two_sizes()
	if _failures.is_empty():
		print("PASS: lobby screen layout tests")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _new_screen(adapter: FakeRealtimeAdapter, viewport_size: Vector2) -> LobbyScreen:
	var screen := LobbyScreen.new()
	screen.set_realtime_adapter(adapter)
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = viewport_size
	root.add_child(screen)
	await process_frame
	return screen


func _test_loading_state_is_distinct_from_empty_state() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var screen := await _new_screen(adapter, Vector2(960, 540))
	adapter.publish_connection_state("connecting")
	await process_frame
	_expect_equal(screen._empty_label.text, "正在加载房间列表", "连接中显示房间列表 loading 文案")
	_expect(screen._empty_label.visible, "连接中保留 loading 状态区域")
	_expect(not screen._room_tree.visible, "连接中不显示空的房间表")
	adapter.publish_connection_state("connected")
	await process_frame
	_expect_equal(screen._empty_label.text, "当前没有可加入的房间", "已连接空列表显示 empty 文案")
	screen.queue_free()
	await process_frame


func _test_empty_state_and_key_regions_fit_at_two_sizes() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var screen := await _new_screen(adapter, Vector2(960, 540))
	adapter.publish_connection_state("connected")
	adapter.publish_rooms([])
	await process_frame
	_assert_key_regions_fit(screen, Vector2(960, 540), "960x540")
	screen.size = Vector2(1280, 720)
	await process_frame
	_assert_key_regions_fit(screen, Vector2(1280, 720), "1280x720")
	screen.queue_free()
	await process_frame


func _test_validation_feedback_is_visible_without_moving_controls() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var screen := await _new_screen(adapter, Vector2(960, 540))
	adapter.publish_connection_state("connected")
	await process_frame
	var connect_rect := screen._connect_button.get_global_rect()
	screen._nickname_input.text = ""
	screen._endpoint_input.text = "http://invalid"
	screen._connect_button.pressed.emit()
	await process_frame
	_expect(screen._feedback_label.text.contains("昵称"), "昵称校验错误可见")
	_expect(screen._feedback_label.get_global_rect().size.y > 0.0, "校验反馈保留稳定区域")
	_expect_equal(screen._connect_button.get_global_rect(), connect_rect, "校验反馈不推动连接按钮")
	screen.queue_free()
	await process_frame


func _test_retry_state_exposes_retry_action() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var screen := await _new_screen(adapter, Vector2(960, 540))
	adapter.publish_connection_state("retryable_error", "服务器暂时不可用")
	await process_frame
	_expect_equal(screen._connect_button.text, "连接大厅", "可重试状态保留连接命令")
	_expect(not screen._connect_button.disabled, "可重试状态连接按钮可用")
	_expect(screen._feedback_label.text.contains("服务器暂时不可用"), "重试错误可见")
	_expect(screen._status_label.text.contains("连接失败"), "顶部状态显示连接失败")
	screen.queue_free()
	await process_frame


func _test_populated_selection_is_readable_at_two_sizes() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var screen := await _new_screen(adapter, Vector2(960, 540))
	adapter.publish_connection_state("connected")
	screen._nickname_input.text = "甲"
	adapter.publish_rooms([
		{"room_id": "room-a", "name": "午休局", "participant_count": 3, "seat_capacity": 4, "deck_mode": "one", "action_deadline_seconds": 30},
		{"room_id": "room-b", "name": "双牌局", "participant_count": 1, "seat_capacity": 4, "deck_mode": "two", "action_deadline_seconds": 60},
	])
	await process_frame
	_expect(screen._room_tree.visible, "有房间时显示房间表")
	_expect(not screen._empty_label.visible, "有房间时隐藏 empty 区域")
	var root_item := screen._room_tree.get_root()
	var first_item := root_item.get_first_child() if root_item != null else null
	if first_item != null:
		screen._room_tree.set_selected(first_item, 0)
		screen._on_room_selected()
		await process_frame
	_expect(not screen._join_button.disabled, "选择房间后加入按钮可用")
	_expect(screen._selection_label.text.contains("午休局"), "选择状态显示房间名称")
	var table_rect := screen._room_tree.get_global_rect()
	_expect(table_rect.position.x >= 0.0 and table_rect.end.x <= 960.0, "960 房间表不越界")
	screen.size = Vector2(1280, 720)
	await process_frame
	_expect(screen._join_button.get_global_rect().end.x <= 1280.0, "1280 加入按钮不越界")
	_expect(screen._selection_label.get_global_rect().end.x <= screen._join_button.get_global_rect().position.x, "选择文案不遮挡加入按钮")
	screen.queue_free()
	await process_frame


func _assert_key_regions_fit(screen: LobbyScreen, viewport_size: Vector2, label: String) -> void:
	for node in [screen._status_panel, screen._split, screen._status_label, screen._connect_button, screen._create_button, screen._room_tree, screen._empty_label, screen._join_button]:
		if node == null or not is_instance_valid(node):
			_failures.append("%s 关键节点缺失" % label)
			continue
		var rect: Rect2 = node.get_global_rect()
		_expect(rect.position.x >= 0.0 and rect.position.y >= 0.0, "%s %s 不越出左上边界" % [label, node.name])
		_expect(rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y, "%s %s 不越出视口" % [label, node.name])
	var entry_panel := screen.find_child("EntryPanel", true, false)
	var rooms_panel := screen.find_child("RoomsPanel", true, false)
	if entry_panel == null or rooms_panel == null:
		_failures.append("%s 左右面板节点缺失" % label)
		return
	var entry_rect: Rect2 = entry_panel.get_global_rect()
	var rooms_rect: Rect2 = rooms_panel.get_global_rect()
	_expect(not entry_rect.intersects(rooms_rect), "%s 左右面板不重叠" % label)


func _expect(condition: bool, context: String) -> void:
	if not condition:
		_failures.append(context)


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
