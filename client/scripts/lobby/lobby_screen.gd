extends Control
class_name LobbyScreen

signal game_room_joined(room_id: String)

const AdapterScript = preload("res://scripts/network/colyseus_realtime_adapter.gd")

const COLOR_BACKGROUND := Color("#121416")
const COLOR_SURFACE := Color("#1b1e20")
const COLOR_SURFACE_RAISED := Color("#222629")
const COLOR_BORDER := Color("#353a3e")
const COLOR_TEXT := Color("#f3f4f4")
const COLOR_MUTED := Color("#9ca3a8")
const COLOR_RED := Color("#d83a3a")
const COLOR_RED_HOVER := Color("#ef4a4a")
const COLOR_GOLD := Color("#e1ad45")
const COLOR_GREEN := Color("#47b881")

var _adapter_override: Object
var _adapter: Object
var _store: LobbyStore
var _selected_room_id := ""

var _split: HSplitContainer
var _status_panel: PanelContainer
var _status_label: Label
var _nickname_input: LineEdit
var _endpoint_input: LineEdit
var _connect_button: Button
var _room_name_input: LineEdit
var _deck_mode_option: OptionButton
var _deadline_option: OptionButton
var _create_button: Button
var _feedback_label: Label
var _room_count_label: Label
var _room_tree: Tree
var _empty_label: Label
var _selection_label: Label
var _join_button: Button
var _rooms_state := "disconnected"


func set_realtime_adapter(adapter: Object) -> void:
	_adapter_override = adapter


func _ready() -> void:
	_build_ui()
	_bind_adapter()
	resized.connect(_apply_responsive_layout)
	_apply_responsive_layout()


func _build_ui() -> void:
	var background := ColorRect.new()
	background.color = COLOR_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	var page := MarginContainer.new()
	page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	page.add_theme_constant_override("margin_left", 20)
	page.add_theme_constant_override("margin_top", 16)
	page.add_theme_constant_override("margin_right", 20)
	page.add_theme_constant_override("margin_bottom", 16)
	add_child(page)

	var page_column := VBoxContainer.new()
	page_column.add_theme_constant_override("separation", 12)
	page.add_child(page_column)

	page_column.add_child(_build_header())

	_split = HSplitContainer.new()
	_split.name = "LobbyWorkspace"
	_split.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_split.split_offset = 284
	_split.add_theme_constant_override("separation", 12)
	page_column.add_child(_split)
	_split.add_child(_build_entry_panel())
	_split.add_child(_build_rooms_panel())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 50
	header.add_theme_constant_override("separation", 12)

	var title_group := VBoxContainer.new()
	title_group.add_theme_constant_override("separation", 0)
	header.add_child(title_group)

	var title := _label("扑克抢红包", 26, COLOR_TEXT)
	title.name = "AppTitle"
	title_group.add_child(title)

	var subtitle := _label("实时大厅 · 固定四人牌局", 13, COLOR_MUTED)
	title_group.add_child(subtitle)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_status_panel = PanelContainer.new()
	_status_panel.custom_minimum_size = Vector2(148, 34)
	_status_panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE_RAISED, COLOR_BORDER, 1, 5))
	header.add_child(_status_panel)

	var status_margin := MarginContainer.new()
	status_margin.add_theme_constant_override("margin_left", 12)
	status_margin.add_theme_constant_override("margin_right", 12)
	status_margin.add_theme_constant_override("margin_top", 5)
	status_margin.add_theme_constant_override("margin_bottom", 5)
	_status_panel.add_child(status_margin)

	_status_label = _label("● 未连接", 14, COLOR_MUTED)
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status_margin.add_child(_status_label)
	return header


func _build_entry_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "EntryPanel"
	panel.custom_minimum_size.x = 270
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE, COLOR_BORDER, 1, 5))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	column.add_child(_section_label("进入大厅"))

	_nickname_input = LineEdit.new()
	_nickname_input.name = "NicknameInput"
	_nickname_input.placeholder_text = "临时昵称"
	_nickname_input.max_length = 20
	_style_input(_nickname_input)
	column.add_child(_form_row("昵称", _nickname_input))

	_endpoint_input = LineEdit.new()
	_endpoint_input.name = "EndpointInput"
	_endpoint_input.text = "ws://127.0.0.1:2567"
	_endpoint_input.placeholder_text = "ws://服务器地址:端口"
	_style_input(_endpoint_input)
	column.add_child(_form_row("服务器", _endpoint_input))

	_connect_button = Button.new()
	_connect_button.name = "ConnectButton"
	_connect_button.text = "连接大厅"
	_connect_button.custom_minimum_size.y = 36
	_style_button(_connect_button, true)
	_connect_button.pressed.connect(_on_connect_pressed)
	column.add_child(_connect_button)

	var divider := HSeparator.new()
	divider.add_theme_constant_override("separation", 10)
	divider.add_theme_stylebox_override("separator", _style_box(COLOR_BORDER, COLOR_BORDER, 0, 0))
	column.add_child(divider)

	column.add_child(_section_label("创建房间"))

	_room_name_input = LineEdit.new()
	_room_name_input.name = "RoomNameInput"
	_room_name_input.placeholder_text = "房间名称"
	_room_name_input.max_length = 24
	_style_input(_room_name_input)
	column.add_child(_form_row("名称", _room_name_input))

	var settings_row := HBoxContainer.new()
	settings_row.add_theme_constant_override("separation", 8)
	column.add_child(settings_row)

	_deck_mode_option = OptionButton.new()
	_deck_mode_option.name = "DeckModeOption"
	_deck_mode_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deck_mode_option.custom_minimum_size.y = 36
	_deck_mode_option.add_item("一副牌")
	_deck_mode_option.set_item_metadata(0, "one")
	_deck_mode_option.add_item("两副牌")
	_deck_mode_option.set_item_metadata(1, "two")
	_style_button(_deck_mode_option)
	settings_row.add_child(_deck_mode_option)

	_deadline_option = OptionButton.new()
	_deadline_option.name = "DeadlineOption"
	_deadline_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_deadline_option.custom_minimum_size.y = 36
	for seconds in [15, 30, 60]:
		_deadline_option.add_item("%d 秒" % seconds)
		_deadline_option.set_item_metadata(_deadline_option.item_count - 1, seconds)
	_deadline_option.select(1)
	_style_button(_deadline_option)
	settings_row.add_child(_deadline_option)

	_create_button = Button.new()
	_create_button.name = "CreateRoomButton"
	_create_button.text = "创建并进入"
	_create_button.custom_minimum_size.y = 36
	_create_button.disabled = true
	_style_button(_create_button, true)
	_create_button.pressed.connect(_on_create_pressed)
	column.add_child(_create_button)

	_feedback_label = _label("", 13, COLOR_MUTED)
	_feedback_label.name = "FeedbackLabel"
	_feedback_label.custom_minimum_size.y = 34
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_feedback_label)

	_nickname_input.text_changed.connect(_on_form_changed)
	_endpoint_input.text_changed.connect(_on_form_changed)
	_room_name_input.text_changed.connect(_on_form_changed)
	return panel


func _build_rooms_panel() -> Control:
	var panel := PanelContainer.new()
	panel.name = "RoomsPanel"
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE, COLOR_BORDER, 1, 5))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 9)
	margin.add_child(column)

	var heading_row := HBoxContainer.new()
	column.add_child(heading_row)
	heading_row.add_child(_section_label("可加入房间"))
	var heading_spacer := Control.new()
	heading_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading_row.add_child(heading_spacer)
	_room_count_label = _label("0 个房间", 13, COLOR_MUTED)
	heading_row.add_child(_room_count_label)

	_room_tree = Tree.new()
	_room_tree.name = "RoomTable"
	_room_tree.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_room_tree.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_tree.hide_root = true
	_room_tree.columns = 5
	_room_tree.column_titles_visible = true
	_room_tree.select_mode = Tree.SELECT_ROW
	_room_tree.set_column_title(0, "房间")
	_room_tree.set_column_title(1, "人数")
	_room_tree.set_column_title(2, "牌组")
	_room_tree.set_column_title(3, "限时")
	_room_tree.set_column_title(4, "房间 ID")
	_room_tree.set_column_expand(0, true)
	_room_tree.set_column_expand_ratio(0, 2)
	_room_tree.set_column_custom_minimum_width(1, 64)
	_room_tree.set_column_expand(1, false)
	_room_tree.set_column_custom_minimum_width(2, 70)
	_room_tree.set_column_expand(2, false)
	_room_tree.set_column_custom_minimum_width(3, 62)
	_room_tree.set_column_expand(3, false)
	_room_tree.set_column_expand(4, true)
	_room_tree.set_column_expand_ratio(4, 1)
	_room_tree.add_theme_font_size_override("font_size", 14)
	_room_tree.add_theme_font_size_override("title_button_font_size", 13)
	_room_tree.add_theme_color_override("font_color", COLOR_TEXT)
	_room_tree.add_theme_color_override("font_selected_color", COLOR_TEXT)
	_room_tree.add_theme_color_override("title_button_color", COLOR_MUTED)
	_room_tree.add_theme_stylebox_override("panel", _style_box(Color("#17191b"), COLOR_BORDER, 1, 4))
	_room_tree.item_selected.connect(_on_room_selected)
	_room_tree.item_activated.connect(_on_room_activated)
	column.add_child(_room_tree)

	_empty_label = _label("当前没有可加入的房间", 15, COLOR_MUTED)
	_empty_label.name = "EmptyRoomsLabel"
	_empty_label.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(_empty_label)

	var action_row := HBoxContainer.new()
	action_row.custom_minimum_size.y = 36
	action_row.add_theme_constant_override("separation", 10)
	column.add_child(action_row)

	_selection_label = _label("请选择一个房间", 13, COLOR_MUTED)
	_selection_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selection_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	action_row.add_child(_selection_label)

	_join_button = Button.new()
	_join_button.name = "JoinRoomButton"
	_join_button.text = "加入所选房间"
	_join_button.custom_minimum_size = Vector2(138, 36)
	_join_button.disabled = true
	_style_button(_join_button, true)
	_join_button.pressed.connect(_on_join_pressed)
	action_row.add_child(_join_button)
	return panel


func _bind_adapter() -> void:
	_adapter = _adapter_override
	if _adapter == null:
		_adapter = AdapterScript.new()
		_adapter.name = "RealtimeAdapter"
		add_child(_adapter)
	_store = LobbyStore.new(_adapter)
	_store.connection_changed.connect(_on_connection_changed)
	_store.rooms_changed.connect(_on_rooms_changed)
	_store.game_room_joined.connect(_on_game_room_joined)
	_store.action_failed.connect(_on_action_failed)
	_on_connection_changed(_store.connection_state, _store.connection_status_text)
	_on_rooms_changed(_store.get_rooms())


func _on_connect_pressed() -> void:
	var nickname := _nickname_input.text.strip_edges()
	var endpoint := _endpoint_input.text.strip_edges()
	if not _valid_nickname(nickname):
		_show_feedback("请输入 1 至 20 个字符的昵称", true)
		_nickname_input.grab_focus()
		return
	if not _valid_endpoint(endpoint):
		_show_feedback("服务器地址必须以 ws:// 或 wss:// 开头", true)
		_endpoint_input.grab_focus()
		return
	_show_feedback("")
	_store.connect_lobby(endpoint, nickname)


func _on_create_pressed() -> void:
	var display_name := _room_name_input.text.strip_edges()
	if display_name.is_empty():
		_show_feedback("请输入房间名称", true)
		_room_name_input.grab_focus()
		return
	_show_feedback("正在创建房间...")
	_store.create_game_room(
		RoomSettings.new(
			display_name,
			str(_deck_mode_option.get_item_metadata(_deck_mode_option.selected)),
			int(_deadline_option.get_item_metadata(_deadline_option.selected))
		),
		_nickname_input.text.strip_edges()
	)


func _on_join_pressed() -> void:
	if _selected_room_id.is_empty():
		return
	_show_feedback("正在加入房间...")
	_store.join_game_room(_selected_room_id, _nickname_input.text.strip_edges())


func _on_room_selected() -> void:
	var selected := _room_tree.get_selected()
	_selected_room_id = str(selected.get_metadata(0)) if selected != null else ""
	_selection_label.text = "已选择：%s" % selected.get_text(0) if selected != null else "请选择一个房间"
	_refresh_action_controls()


func _on_room_activated() -> void:
	_on_room_selected()
	if not _join_button.disabled:
		_on_join_pressed()


func _on_connection_changed(state: String, status_text: String) -> void:
	_rooms_state = state
	var status_color := COLOR_MUTED
	match state:
		"connecting":
			status_color = COLOR_GOLD
		"connected":
			status_color = COLOR_GREEN
		"retryable_error":
			status_color = COLOR_RED_HOVER
	_status_label.text = "● %s" % status_text
	_status_label.add_theme_color_override("font_color", status_color)
	_status_panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE_RAISED, status_color.darkened(0.45), 1, 5))
	_connect_button.text = "连接中..." if state == "connecting" else ("重新连接" if state == "connected" else "连接大厅")
	_connect_button.disabled = state == "connecting"
	if state == "retryable_error":
		_show_feedback(status_text, true)
	_refresh_rooms_surface()
	_refresh_action_controls()


func _on_rooms_changed(rooms: Array[Dictionary]) -> void:
	var previous_selection := _selected_room_id
	_selected_room_id = ""
	_room_tree.clear()
	var root_item := _room_tree.create_item()
	for room in rooms:
		var item := _room_tree.create_item(root_item)
		var room_id := str(room.get("room_id", ""))
		item.set_text(0, str(room.get("name", "未命名房间")))
		item.set_text(1, "%d / %d" % [int(room.get("participant_count", 0)), int(room.get("seat_capacity", 4))])
		item.set_text(2, "两副牌" if str(room.get("deck_mode", "one")) == "two" else "一副牌")
		item.set_text(3, "%d 秒" % int(room.get("action_deadline_seconds", 30)))
		item.set_text(4, room_id)
		item.set_metadata(0, room_id)
		if room_id == previous_selection:
			item.select(0)
			_selected_room_id = room_id

	_room_count_label.text = "%d 个房间" % rooms.size()
	_refresh_rooms_surface()
	if _selected_room_id.is_empty():
		_selection_label.text = "请选择一个房间"
	_refresh_action_controls()


func _refresh_rooms_surface() -> void:
	if _room_tree == null or _empty_label == null:
		return
	var has_rooms := _room_tree.get_root() != null and _room_tree.get_root().get_first_child() != null
	match _rooms_state:
		"connecting":
			_empty_label.text = "正在加载房间列表"
			_room_tree.visible = false
			_empty_label.visible = true
		"retryable_error":
			_empty_label.text = "房间列表加载失败，请重试"
			_room_tree.visible = false
			_empty_label.visible = true
		"connected":
			_empty_label.text = "当前没有可加入的房间"
			_room_tree.visible = has_rooms
			_empty_label.visible = not has_rooms
		_:
			_empty_label.text = "连接大厅后查看房间"
			_room_tree.visible = false
			_empty_label.visible = true


func _on_game_room_joined(room_id: String) -> void:
	_show_feedback("已加入房间：%s" % room_id)
	game_room_joined.emit(room_id)


func _on_action_failed(message: String) -> void:
	_show_feedback("房间操作失败：%s" % message, true)


func _on_form_changed(_text: String) -> void:
	_refresh_action_controls()


func _refresh_action_controls() -> void:
	if _store == null:
		return
	var connected := _store.connection_state == "connected"
	_create_button.disabled = not connected or not _valid_nickname(_nickname_input.text.strip_edges()) or _room_name_input.text.strip_edges().is_empty()
	_join_button.disabled = not connected or not _valid_nickname(_nickname_input.text.strip_edges()) or _selected_room_id.is_empty()


func _show_feedback(message: String, is_error := false) -> void:
	_feedback_label.text = message
	_feedback_label.add_theme_color_override("font_color", COLOR_RED_HOVER if is_error else COLOR_MUTED)


func _valid_nickname(nickname: String) -> bool:
	return nickname.length() >= 1 and nickname.length() <= 20


func _valid_endpoint(endpoint: String) -> bool:
	return endpoint.begins_with("ws://") or endpoint.begins_with("wss://")


func _apply_responsive_layout() -> void:
	if _split == null:
		return
	_split.split_offset = 258 if size.x <= 1024.0 else 284


func _form_row(caption: String, input: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 36
	row.add_theme_constant_override("separation", 8)
	var caption_label := _label(caption, 13, COLOR_MUTED)
	caption_label.custom_minimum_size.x = 50
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption_label)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	return row


func _section_label(text: String) -> Label:
	var result := _label(text, 17, COLOR_TEXT)
	result.custom_minimum_size.y = 24
	result.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	return result


func _label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


func _style_input(input: LineEdit) -> void:
	input.custom_minimum_size.y = 36
	input.add_theme_font_size_override("font_size", 14)
	input.add_theme_color_override("font_color", COLOR_TEXT)
	input.add_theme_color_override("font_placeholder_color", COLOR_MUTED.darkened(0.2))
	input.add_theme_color_override("caret_color", COLOR_GOLD)
	input.add_theme_stylebox_override("normal", _style_box(Color("#17191b"), COLOR_BORDER, 1, 4, 9))
	input.add_theme_stylebox_override("focus", _style_box(Color("#17191b"), COLOR_GOLD.darkened(0.15), 1, 4, 9))


func _style_button(button: BaseButton, primary := false) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_hover_color", COLOR_TEXT)
	button.add_theme_color_override("font_pressed_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED.darkened(0.25))
	if primary:
		button.add_theme_stylebox_override("normal", _style_box(COLOR_RED, COLOR_RED, 0, 4, 10))
		button.add_theme_stylebox_override("hover", _style_box(COLOR_RED_HOVER, COLOR_RED_HOVER, 0, 4, 10))
		button.add_theme_stylebox_override("pressed", _style_box(COLOR_RED.darkened(0.18), COLOR_RED, 0, 4, 10))
	else:
		button.add_theme_stylebox_override("normal", _style_box(COLOR_SURFACE_RAISED, COLOR_BORDER, 1, 4, 10))
		button.add_theme_stylebox_override("hover", _style_box(Color("#2b3033"), COLOR_GOLD.darkened(0.2), 1, 4, 10))
		button.add_theme_stylebox_override("pressed", _style_box(Color("#17191b"), COLOR_GOLD.darkened(0.2), 1, 4, 10))
	button.add_theme_stylebox_override("disabled", _style_box(Color("#202326"), Color("#2b3033"), 1, 4, 10))
	button.add_theme_stylebox_override("focus", _style_box(Color(0, 0, 0, 0), COLOR_GOLD, 1, 4, 9))


func _style_box(
	fill: Color,
	border: Color,
	border_width: int,
	radius: int,
	horizontal_padding := 0
) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.content_margin_left = horizontal_padding
	style.content_margin_right = horizontal_padding
	return style
