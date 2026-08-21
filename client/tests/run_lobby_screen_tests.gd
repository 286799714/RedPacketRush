extends "res://tests/screen_test_runner.gd"

const FakeRealtimeAdapter = preload("res://tests/fakes/fake_realtime_adapter.gd")
const LobbyScreen = preload("res://scripts/lobby/lobby_screen.gd")

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
	var room_tree := _find_room_tree(screen)
	adapter.publish_connection_state("connecting")
	await process_frame
	_expect(_find_visible_label_containing(screen, "正在加载房间列表") != null, "连接中显示房间列表 loading 文案")
	_expect(room_tree != null and not room_tree.visible, "连接中不显示空的房间表")
	adapter.publish_connection_state("connected")
	await process_frame
	_expect(_find_visible_label_containing(screen, "当前没有可加入的房间") != null, "已连接空列表显示 empty 文案")
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
	var connect_button := _find_visible_button(screen, "重新连接")
	var nickname_input := _find_line_edit_by_placeholder(screen, "临时昵称")
	var endpoint_input := _find_line_edit_by_placeholder(screen, "ws://服务器地址:端口")
	_expect(connect_button != null and nickname_input != null and endpoint_input != null, "大厅连接表单控件可见")
	if connect_button == null or nickname_input == null or endpoint_input == null:
		screen.queue_free()
		await process_frame
		return
	var connect_rect := connect_button.get_global_rect()
	nickname_input.text = ""
	endpoint_input.text = "http://invalid"
	connect_button.pressed.emit()
	await process_frame
	var feedback := _find_visible_label_containing(screen, "请输入 1 至 20 个字符的昵称")
	_expect(feedback != null, "昵称校验错误可见")
	_expect(feedback != null and feedback.get_global_rect().size.y > 0.0, "校验反馈保留稳定区域")
	_expect_equal(connect_button.get_global_rect(), connect_rect, "校验反馈不推动连接按钮")
	screen.queue_free()
	await process_frame


func _test_retry_state_exposes_retry_action() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var screen := await _new_screen(adapter, Vector2(960, 540))
	adapter.publish_connection_state("retryable_error", "服务器暂时不可用")
	await process_frame
	var connect_button := _find_visible_button(screen, "连接大厅")
	_expect(connect_button != null, "可重试状态保留连接命令")
	_expect(connect_button != null and not connect_button.disabled, "可重试状态连接按钮可用")
	_expect(_find_visible_label_containing(screen, "服务器暂时不可用") != null, "重试错误可见")
	_expect(_find_visible_label_containing(screen, "连接失败") != null, "顶部状态显示连接失败")
	screen.queue_free()
	await process_frame


func _test_populated_selection_is_readable_at_two_sizes() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var screen := await _new_screen(adapter, Vector2(960, 540))
	adapter.publish_connection_state("connected")
	var nickname_input := _find_line_edit_by_placeholder(screen, "临时昵称")
	if nickname_input != null:
		nickname_input.text = "甲"
	adapter.publish_rooms([
		{"room_id": "room-a", "name": "午休局", "participant_count": 3, "seat_capacity": 4, "deck_mode": "one", "action_deadline_seconds": 30},
		{"room_id": "room-b", "name": "双牌局", "participant_count": 1, "seat_capacity": 4, "deck_mode": "two", "action_deadline_seconds": 60},
	])
	await process_frame
	var room_tree := _find_room_tree(screen)
	_expect(nickname_input != null, "昵称输入可见")
	_expect(room_tree != null and room_tree.visible, "有房间时显示房间表")
	_expect(_find_visible_label_containing(screen, "当前没有可加入的房间") == null, "有房间时隐藏 empty 区域")
	var root_item := room_tree.get_root() if room_tree != null else null
	var first_item := root_item.get_first_child() if root_item != null else null
	if room_tree != null and first_item != null:
		room_tree.set_selected(first_item, 0)
		room_tree.item_selected.emit()
		await process_frame
	var join_button := _find_visible_button(screen, "加入所选房间")
	var selection_label := _find_visible_label_containing(screen, "已选择：午休局")
	_expect(join_button != null and not join_button.disabled, "选择房间后加入按钮可用")
	_expect(selection_label != null, "选择状态显示房间名称")
	if room_tree != null:
		var table_rect := room_tree.get_global_rect()
		_expect(table_rect.position.x >= 0.0 and table_rect.end.x <= 960.0, "960 房间表不越界")
	screen.size = Vector2(1280, 720)
	await process_frame
	if join_button != null:
		_expect(join_button.get_global_rect().end.x <= 1280.0, "1280 加入按钮不越界")
	if selection_label != null and join_button != null:
		_expect(selection_label.get_global_rect().end.x <= join_button.get_global_rect().position.x, "选择文案不遮挡加入按钮")
	screen.queue_free()
	await process_frame


func _assert_key_regions_fit(screen: LobbyScreen, viewport_size: Vector2, label: String) -> void:
	var nodes: Array[Control] = []
	for node in [
		screen.find_child("LobbyWorkspace", true, false),
		screen.find_child("EntryPanel", true, false),
		screen.find_child("RoomsPanel", true, false),
		_find_visible_label_containing(screen, "已连接"),
		_find_visible_button(screen, "重新连接"),
		_find_visible_button(screen, "创建并进入"),
		_find_room_tree(screen),
		_find_visible_label_containing(screen, "当前没有可加入的房间"),
		_find_visible_button(screen, "加入所选房间"),
	]:
		if node is Control:
			nodes.append(node)
	_expect_equal(nodes.size(), 9, "%s 大厅关键区域可见" % label)
	for node in nodes:
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


func _find_room_tree(root_node: Node) -> Tree:
	for node in root_node.find_children("*", "Tree", true, false):
		if node is Tree:
			return node
	return null


func _find_line_edit_by_placeholder(root_node: Node, placeholder: String) -> LineEdit:
	for node in root_node.find_children("*", "LineEdit", true, false):
		if node is LineEdit and node.is_visible_in_tree() and node.placeholder_text == placeholder:
			return node
	return null
