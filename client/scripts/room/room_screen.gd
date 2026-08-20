extends Control
class_name RoomScreen

const RoomConfigurationScript = preload("res://scripts/domain/room_configuration.gd")

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

var _store_override: Object
var _store: Object
var _updating_controls := false

var _room_name_label: Label
var _room_id_label: Label
var _status_label: Label
var _leave_button: Button
var _seat_panels: Array[PanelContainer] = []
var _seat_name_labels: Array[Label] = []
var _seat_detail_labels: Array[Label] = []
var _seat_role_labels: Array[Label] = []
var _deck_mode_option: OptionButton
var _deadline_option: OptionButton
var _ready_toggle: CheckButton
var _fill_bots_button: Button
var _start_button: Button
var _feedback_label: Label


func set_room_store(store: Object) -> void:
	_store_override = store


func _ready() -> void:
	_store = _store_override
	_build_ui()
	if _store == null:
		_show_feedback("房间状态不可用", true)
		return
	_store.state_changed.connect(_refresh)
	_store.action_failed.connect(_on_action_failed)
	_refresh()


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

	var workspace := HBoxContainer.new()
	workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	workspace.add_theme_constant_override("separation", 12)
	page_column.add_child(workspace)
	workspace.add_child(_build_seat_workspace())
	workspace.add_child(_build_controls_panel())


func _build_header() -> Control:
	var header := HBoxContainer.new()
	header.custom_minimum_size.y = 50
	header.add_theme_constant_override("separation", 12)
	header.clip_contents = true

	var title_group := VBoxContainer.new()
	title_group.add_theme_constant_override("separation", 0)
	title_group.custom_minimum_size.x = 0
	title_group.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(title_group)
	_room_name_label = _label("正在进入房间", 24, COLOR_TEXT)
	_room_name_label.custom_minimum_size.x = 0
	_room_name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_name_label.clip_text = true
	_room_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_group.add_child(_room_name_label)
	_room_id_label = _label("", 12, COLOR_MUTED)
	_room_id_label.custom_minimum_size.x = 0
	_room_id_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_room_id_label.clip_text = true
	_room_id_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_group.add_child(_room_id_label)

	_status_label = _label("等待状态", 14, COLOR_GOLD)
	_status_label.custom_minimum_size = Vector2(110, 34)
	_status_label.size_flags_horizontal = Control.SIZE_SHRINK_END
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_status_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_status_label)

	_leave_button = Button.new()
	_leave_button.text = "离开房间"
	_leave_button.custom_minimum_size = Vector2(108, 36)
	_style_button(_leave_button)
	_leave_button.pressed.connect(_on_leave_pressed)
	header.add_child(_leave_button)
	return header


func _build_seat_workspace() -> Control:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 9)
	column.add_child(_label("参与者席位", 17, COLOR_TEXT))

	var grid := GridContainer.new()
	grid.columns = 2
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", 10)
	grid.add_theme_constant_override("v_separation", 10)
	column.add_child(grid)
	for seat_index in range(4):
		grid.add_child(_build_seat_panel(seat_index))
	return column


func _build_seat_panel(seat_index: int) -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(250, 154)
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE, COLOR_BORDER, 1, 5))
	_seat_panels.append(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 14)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 14)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)

	var heading := HBoxContainer.new()
	column.add_child(heading)
	heading.add_child(_label("席位 %d" % (seat_index + 1), 13, COLOR_MUTED))
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(spacer)
	var role := _label("", 12, COLOR_GOLD)
	heading.add_child(role)
	_seat_role_labels.append(role)

	var name_label := _label("等待参与者", 20, COLOR_TEXT)
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	_seat_name_labels.append(name_label)
	var detail := _label("空座", 13, COLOR_MUTED)
	detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(detail)
	_seat_detail_labels.append(detail)
	return panel


func _build_controls_panel() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = 310
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE, COLOR_BORDER, 1, 5))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 15)
	margin.add_theme_constant_override("margin_top", 14)
	margin.add_theme_constant_override("margin_right", 15)
	margin.add_theme_constant_override("margin_bottom", 14)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	margin.add_child(column)
	column.add_child(_label("房间设置", 17, COLOR_TEXT))

	_deck_mode_option = OptionButton.new()
	_deck_mode_option.add_item("一副牌")
	_deck_mode_option.set_item_metadata(0, "one")
	_deck_mode_option.add_item("两副牌")
	_deck_mode_option.set_item_metadata(1, "two")
	_style_button(_deck_mode_option)
	column.add_child(_form_row("牌组", _deck_mode_option))

	_deadline_option = OptionButton.new()
	for seconds in [15, 30, 60]:
		_deadline_option.add_item("%d 秒" % seconds)
		_deadline_option.set_item_metadata(_deadline_option.item_count - 1, seconds)
	_style_button(_deadline_option)
	column.add_child(_form_row("限时", _deadline_option))
	_deck_mode_option.item_selected.connect(_on_setting_selected)
	_deadline_option.item_selected.connect(_on_setting_selected)

	var divider := HSeparator.new()
	divider.add_theme_stylebox_override("separator", _style_box(COLOR_BORDER, COLOR_BORDER, 0, 0))
	column.add_child(divider)

	_ready_toggle = CheckButton.new()
	_ready_toggle.text = "我已准备"
	_ready_toggle.custom_minimum_size.y = 40
	_ready_toggle.add_theme_font_size_override("font_size", 15)
	_ready_toggle.add_theme_color_override("font_color", COLOR_TEXT)
	_ready_toggle.toggled.connect(_on_ready_toggled)
	column.add_child(_ready_toggle)

	_fill_bots_button = Button.new()
	_fill_bots_button.text = "填满机器人"
	_fill_bots_button.custom_minimum_size.y = 38
	_style_button(_fill_bots_button)
	_fill_bots_button.pressed.connect(func(): _store.fill_bots())
	column.add_child(_fill_bots_button)

	_start_button = Button.new()
	_start_button.text = "开始对局"
	_start_button.custom_minimum_size.y = 42
	_style_button(_start_button, true)
	_start_button.pressed.connect(func(): _store.start_match())
	column.add_child(_start_button)

	_feedback_label = _label("", 13, COLOR_MUTED)
	_feedback_label.custom_minimum_size.y = 50
	_feedback_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(_feedback_label)
	return panel


func _refresh() -> void:
	if _store == null:
		return
	_updating_controls = true
	_room_name_label.text = _store.display_name if not _store.display_name.is_empty() else "正在同步房间"
	_room_id_label.text = "房间 ID  %s" % _store.room_id if not _store.room_id.is_empty() else "等待服务器状态"
	match _store.status:
		"waiting":
			_status_label.text = "等待准备"
		"started":
			_status_label.text = "对局开始"
		_:
			_status_label.text = "同步中"
	_status_label.add_theme_color_override(
		"font_color",
		COLOR_GOLD if _store.status == "waiting" else COLOR_GREEN
	)

	var seats: Array[Dictionary] = _store.get_seats()
	for seat_index in range(4):
		var seat: Dictionary = seats[seat_index] if seat_index < seats.size() else {}
		_refresh_seat(seat_index, seat)

	_deck_mode_option.select(1 if _store.deck_mode == "two" else 0)
	for option_index in range(_deadline_option.item_count):
		if int(_deadline_option.get_item_metadata(option_index)) == _store.action_deadline_seconds:
			_deadline_option.select(option_index)
			break
	_deck_mode_option.disabled = not _store.can_configure()
	_deadline_option.disabled = not _store.can_configure()
	_ready_toggle.disabled = not _store.can_toggle_ready()
	_ready_toggle.button_pressed = _store.is_local_ready()
	_fill_bots_button.disabled = not _store.can_fill_bots()
	_start_button.disabled = not _store.can_start()
	if _store.status == "started":
		_show_feedback("对局正在开始...")
	elif _store.is_local_host():
		_show_feedback("你是房主")
	else:
		_show_feedback("等待房主准备房间")
	_updating_controls = false


func _refresh_seat(seat_index: int, seat: Dictionary) -> void:
	var participant_id := str(seat.get("participant_id", ""))
	var occupied := not participant_id.is_empty()
	var is_bot := bool(seat.get("is_bot", false))
	var is_ready := bool(seat.get("is_ready", false))
	_seat_name_labels[seat_index].text = str(seat.get("nickname", "")) if occupied else "等待参与者"
	_seat_detail_labels[seat_index].text = (
		("机器人" if is_bot else "人类") + (" · 已准备" if is_ready else " · 未准备")
		if occupied else "空座"
	)
	var roles: Array[String] = []
	if participant_id == _store.host_participant_id:
		roles.append("房主")
	if participant_id == _store.local_participant_id:
		roles.append("你")
	_seat_role_labels[seat_index].text = " · ".join(roles)
	var border := COLOR_GREEN.darkened(0.25) if is_ready else COLOR_BORDER
	_seat_panels[seat_index].add_theme_stylebox_override(
		"panel",
		_style_box(COLOR_SURFACE_RAISED if occupied else COLOR_SURFACE, border, 1, 5)
	)


func _on_setting_selected(_index: int) -> void:
	if _updating_controls or _store == null or not _store.can_configure():
		return
	_store.configure_room(RoomConfigurationScript.new(
		str(_deck_mode_option.get_item_metadata(_deck_mode_option.selected)),
		int(_deadline_option.get_item_metadata(_deadline_option.selected))
	))


func _on_ready_toggled(ready: bool) -> void:
	if not _updating_controls and _store != null and _store.can_toggle_ready():
		_store.set_ready(ready)


func _on_leave_pressed() -> void:
	if _store != null:
		_store.leave_room()


func _on_action_failed(_code: String, message: String) -> void:
	_show_feedback(message, true)


func _show_feedback(message: String, is_error := false) -> void:
	_feedback_label.text = message
	_feedback_label.add_theme_color_override("font_color", COLOR_RED_HOVER if is_error else COLOR_MUTED)


func _form_row(caption: String, input: Control) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.custom_minimum_size.y = 38
	row.add_theme_constant_override("separation", 8)
	var caption_label := _label(caption, 13, COLOR_MUTED)
	caption_label.custom_minimum_size.x = 50
	caption_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(caption_label)
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	return row


func _label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


func _style_button(button: BaseButton, primary := false) -> void:
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.add_theme_font_size_override("font_size", 14)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_color_override("font_disabled_color", COLOR_MUTED.darkened(0.25))
	if primary:
		button.add_theme_stylebox_override("normal", _style_box(COLOR_RED, COLOR_RED, 0, 4, 10))
		button.add_theme_stylebox_override("hover", _style_box(COLOR_RED_HOVER, COLOR_RED_HOVER, 0, 4, 10))
	else:
		button.add_theme_stylebox_override("normal", _style_box(COLOR_SURFACE_RAISED, COLOR_BORDER, 1, 4, 10))
		button.add_theme_stylebox_override("hover", _style_box(Color("#2b3033"), COLOR_GOLD.darkened(0.2), 1, 4, 10))
	button.add_theme_stylebox_override("disabled", _style_box(Color("#202326"), Color("#2b3033"), 1, 4, 10))


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
