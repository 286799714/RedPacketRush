extends Control
class_name MatchScreen

## Dense public match table.  The screen deliberately consumes a very small
## store protocol so that private data never has to pass through the scene.

const COLOR_BACKGROUND := Color("#121416")
const COLOR_TABLE := Color("#172321")
const COLOR_TABLE_LINE := Color("#2b413b")
const COLOR_SURFACE := Color("#1b1e20")
const COLOR_SURFACE_RAISED := Color("#222629")
const COLOR_BORDER := Color("#353a3e")
const COLOR_TEXT := Color("#f3f4f4")
const COLOR_MUTED := Color("#9ca3a8")
const COLOR_GOLD := Color("#e1ad45")
const COLOR_GREEN := Color("#47b881")
const COLOR_HEARTS := Color("#ec7777")
const COLOR_DIAMONDS := Color("#ec7777")
const COLOR_BLACK_SUIT := Color("#d7dcdf")

const SEAT_WIDTH := 176.0
const SEAT_HEIGHT := 58.0
const HAND_PANEL_HEIGHT := 138.0
const CARD_WIDTH := 68.0
const CARD_HEIGHT := 82.0

var _store_override: Object
var _store: Object
var _bound_store: Object

var _page: MarginContainer
var _header: HBoxContainer
var _phase_label: Label
var _actor_label: Label
var _deck_label: Label
var _connection_label: Label
var _workspace: HBoxContainer
var _history_panel: PanelContainer
var _history_list: VBoxContainer
var _history_scroll: ScrollContainer
var _table_area: Control
var _table_surface: ColorRect
var _contest_panel: PanelContainer
var _contest_title_label: Label
var _contest_detail_label: Label
var _contest_reveal_row: HBoxContainer
var _hand_panel: PanelContainer
var _hand_title_label: Label
var _hand_row: HBoxContainer
var _action_bar: PanelContainer
var _action_prompt_label: Label

var _seat_cards: Array[PanelContainer] = []
var _seat_position_labels: Array[Label] = []
var _seat_name_labels: Array[Label] = []
var _seat_detail_labels: Array[Label] = []
var _seat_role_labels: Array[Label] = []
var _hand_cards: Array[PanelContainer] = []

var _participant_by_seat: Dictionary = {}
var _local_seat_index := -1


func set_match_store(store: Object) -> void:
	_store_override = store
	if is_inside_tree():
		_unbind_store()
		_store = store
		_bind_store()
		_refresh()


func _ready() -> void:
	_build_ui()
	_store = _store_override
	_bind_store()
	_refresh()
	_table_area.resized.connect(_on_resized)
	call_deferred("_on_resized")


func _exit_tree() -> void:
	_unbind_store()


func _bind_store() -> void:
	if _store == null or _bound_store == _store:
		return
	_bound_store = _store
	if _store.has_signal("state_changed"):
		_store.state_changed.connect(_on_store_changed)
	if _store.has_signal("private_state_changed"):
		_store.private_state_changed.connect(_on_store_changed)


func _unbind_store() -> void:
	if _bound_store == null:
		return
	var callback := Callable(self, "_on_store_changed")
	if _bound_store.has_signal("state_changed") and _bound_store.is_connected("state_changed", callback):
		_bound_store.disconnect("state_changed", callback)
	if _bound_store.has_signal("private_state_changed") and _bound_store.is_connected("private_state_changed", callback):
		_bound_store.disconnect("private_state_changed", callback)
	_bound_store = null


func _on_store_changed(_first: Variant = null, _second: Variant = null, _third: Variant = null) -> void:
	_refresh()


func _build_ui() -> void:
	set_process_input(false)

	var background := ColorRect.new()
	background.name = "Background"
	background.color = COLOR_BACKGROUND
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(background)

	_page = MarginContainer.new()
	_page.name = "Page"
	_page.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_page.add_theme_constant_override("margin_left", 12)
	_page.add_theme_constant_override("margin_top", 10)
	_page.add_theme_constant_override("margin_right", 12)
	_page.add_theme_constant_override("margin_bottom", 10)
	add_child(_page)

	var column := VBoxContainer.new()
	column.name = "PageColumn"
	column.add_theme_constant_override("separation", 8)
	_page.add_child(column)

	_header = _build_header()
	column.add_child(_header)
	_workspace = HBoxContainer.new()
	_workspace.name = "MatchWorkspace"
	_workspace.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_workspace.add_theme_constant_override("separation", 10)
	column.add_child(_workspace)
	_workspace.add_child(_build_history_panel())
	_workspace.add_child(_build_table_area())


func _build_header() -> HBoxContainer:
	var header := HBoxContainer.new()
	header.name = "MatchHeader"
	header.custom_minimum_size.y = 44
	header.add_theme_constant_override("separation", 10)

	_phase_label = _label("阶段：同步中", 17, COLOR_TEXT)
	_phase_label.name = "PhaseLabel"
	_phase_label.custom_minimum_size = Vector2(178, 42)
	_phase_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_phase_label.clip_text = true
	header.add_child(_phase_label)

	_actor_label = _label("行动者：等待", 14, COLOR_GOLD)
	_actor_label.name = "ActorLabel"
	_actor_label.custom_minimum_size = Vector2(220, 42)
	_actor_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_actor_label.clip_text = true
	_actor_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	header.add_child(_actor_label)

	_deck_label = _label("牌堆：--", 14, COLOR_MUTED)
	_deck_label.name = "DeckLabel"
	_deck_label.custom_minimum_size = Vector2(120, 42)
	_deck_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_deck_label)

	var spacer := Control.new()
	spacer.name = "HeaderSpacer"
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(spacer)

	_connection_label = _label("公开状态", 13, COLOR_MUTED)
	_connection_label.name = "ConnectionLabel"
	_connection_label.custom_minimum_size = Vector2(84, 42)
	_connection_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_connection_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(_connection_label)
	return header


func _build_history_panel() -> PanelContainer:
	_history_panel = PanelContainer.new()
	_history_panel.name = "ContestHistoryPanel"
	_history_panel.custom_minimum_size.x = 198
	_history_panel.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_history_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE, COLOR_BORDER, 1, 5))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 9)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 9)
	_history_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 6)
	margin.add_child(column)
	var title := _label("拼点历史", 16, COLOR_TEXT)
	title.name = "ContestHistoryTitle"
	title.custom_minimum_size.y = 24
	column.add_child(title)
	_history_scroll = ScrollContainer.new()
	_history_scroll.name = "ContestHistoryScroll"
	_history_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_history_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(_history_scroll)
	_history_list = VBoxContainer.new()
	_history_list.name = "ContestHistoryList"
	_history_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_history_list.add_theme_constant_override("separation", 6)
	_history_scroll.add_child(_history_list)
	return _history_panel


func _build_table_area() -> Control:
	_table_area = Control.new()
	_table_area.name = "MatchTable"
	_table_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_table_area.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_table_area.clip_contents = true

	_table_surface = ColorRect.new()
	_table_surface.name = "TableSurface"
	_table_surface.color = COLOR_TABLE
	_table_surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_table_surface.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_table_area.add_child(_table_surface)

	_contest_panel = PanelContainer.new()
	_contest_panel.name = "LatestContest"
	_contest_panel.add_theme_stylebox_override("panel", _style_box(Color("#1d2b28"), COLOR_TABLE_LINE, 1, 5))
	_table_area.add_child(_contest_panel)
	var contest_margin := MarginContainer.new()
	contest_margin.add_theme_constant_override("margin_left", 9)
	contest_margin.add_theme_constant_override("margin_top", 6)
	contest_margin.add_theme_constant_override("margin_right", 9)
	contest_margin.add_theme_constant_override("margin_bottom", 6)
	_contest_panel.add_child(contest_margin)
	var contest_column := VBoxContainer.new()
	contest_column.add_theme_constant_override("separation", 3)
	contest_margin.add_child(contest_column)
	_contest_title_label = _label("最新拼点", 13, COLOR_GOLD)
	_contest_title_label.name = "LatestContestTitle"
	contest_column.add_child(_contest_title_label)
	_contest_detail_label = _label("等待公开翻牌", 12, COLOR_MUTED)
	_contest_detail_label.name = "LatestContestDetail"
	_contest_detail_label.clip_text = true
	_contest_detail_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	contest_column.add_child(_contest_detail_label)
	_contest_reveal_row = HBoxContainer.new()
	_contest_reveal_row.name = "LatestContestReveals"
	_contest_reveal_row.add_theme_constant_override("separation", 5)
	contest_column.add_child(_contest_reveal_row)

	for seat_index in range(4):
		_build_seat_card(seat_index)

	_hand_panel = PanelContainer.new()
	_hand_panel.name = "LocalHandPanel"
	_hand_panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE, COLOR_BORDER, 1, 5))
	_table_area.add_child(_hand_panel)
	var hand_margin := MarginContainer.new()
	hand_margin.add_theme_constant_override("margin_left", 9)
	hand_margin.add_theme_constant_override("margin_top", 5)
	hand_margin.add_theme_constant_override("margin_right", 9)
	hand_margin.add_theme_constant_override("margin_bottom", 5)
	_hand_panel.add_child(hand_margin)
	var hand_column := VBoxContainer.new()
	hand_column.add_theme_constant_override("separation", 4)
	hand_margin.add_child(hand_column)
	_hand_title_label = _label("我的手牌（8）", 13, COLOR_TEXT)
	_hand_title_label.name = "LocalHandTitle"
	_hand_title_label.custom_minimum_size.y = 20
	hand_column.add_child(_hand_title_label)
	_hand_row = HBoxContainer.new()
	_hand_row.name = "LocalHand"
	_hand_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hand_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hand_row.add_theme_constant_override("separation", 6)
	hand_column.add_child(_hand_row)
	_action_bar = PanelContainer.new()
	_action_bar.name = "ActionBar"
	_action_bar.custom_minimum_size.y = 29
	_action_bar.add_theme_stylebox_override("panel", _style_box(Color("#20282a"), COLOR_TABLE_LINE, 1, 4))
	hand_column.add_child(_action_bar)
	var action_margin := MarginContainer.new()
	action_margin.add_theme_constant_override("margin_left", 8)
	action_margin.add_theme_constant_override("margin_right", 8)
	_action_bar.add_child(action_margin)
	_action_prompt_label = _label("等待服务器状态", 12, COLOR_MUTED)
	_action_prompt_label.name = "ActionPrompt"
	_action_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_prompt_label.clip_text = true
	_action_prompt_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	action_margin.add_child(_action_prompt_label)
	return _table_area


func _build_seat_card(seat_index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "Seat%d" % seat_index
	panel.custom_minimum_size = Vector2(SEAT_WIDTH, SEAT_HEIGHT)
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE_RAISED, COLOR_BORDER, 1, 5))
	_table_area.add_child(panel)
	_seat_cards.append(panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_top", 5)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 5)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	margin.add_child(column)
	var heading := HBoxContainer.new()
	heading.add_theme_constant_override("separation", 4)
	column.add_child(heading)
	var position_label := _label("席位", 11, COLOR_MUTED)
	position_label.name = "SeatPosition%d" % seat_index
	heading.add_child(position_label)
	_seat_position_labels.append(position_label)
	var heading_spacer := Control.new()
	heading_spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(heading_spacer)
	var role := _label("", 11, COLOR_GOLD)
	role.name = "SeatRole%d" % seat_index
	role.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	role.clip_text = true
	role.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	heading.add_child(role)
	_seat_role_labels.append(role)
	var name_label := _label("等待参与者", 15, COLOR_TEXT)
	name_label.name = "SeatName%d" % seat_index
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(name_label)
	_seat_name_labels.append(name_label)
	var detail := _label("空席", 11, COLOR_MUTED)
	detail.name = "SeatDetail%d" % seat_index
	detail.clip_text = true
	detail.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(detail)
	_seat_detail_labels.append(detail)
	return panel


func _refresh() -> void:
	if _store == null:
		_participant_by_seat.clear()
		_phase_label.text = "阶段：同步中"
		_actor_label.text = "行动者：等待"
		_deck_label.text = "牌堆：--"
		_connection_label.text = "等待状态"
		_action_prompt_label.text = "等待服务器状态"
		_refresh_seats(-1, -1)
		_refresh_history([])
		_clear_hand()
		return

	var participants: Array[Dictionary] = _store.get_participants()
	_participant_by_seat.clear()
	for participant in participants:
		var seat_index := int(participant.get("seat_index", -1))
		if seat_index >= 0 and seat_index < 4:
			_participant_by_seat[seat_index] = participant
	var local_seat_index := _find_local_seat_index()
	_local_seat_index = local_seat_index
	var phase := str(_store.phase)
	var actor_seat_index := int(_store.actor_seat_index)
	_phase_label.text = "阶段：%s" % _phase_text(phase)
	_actor_label.text = "行动者：%s" % _participant_name(actor_seat_index)
	_deck_label.text = "牌堆：%d" % int(_store.draw_pile_count)
	_connection_label.text = "公开状态"
	_refresh_seats(local_seat_index, actor_seat_index)
	_refresh_history(_store.get_contest_rounds())
	_refresh_hand()
	_refresh_action_prompt(phase, actor_seat_index, local_seat_index)


func _find_local_seat_index() -> int:
	var local_id := str(_store.local_participant_id)
	for seat_index in _participant_by_seat.keys():
		var participant: Dictionary = _participant_by_seat[seat_index]
		if str(participant.get("participant_id", "")) == local_id:
			return int(seat_index)
	return -1


func _refresh_seats(local_seat_index: int, actor_seat_index: int) -> void:
	for seat_index in range(4):
		var participant: Dictionary = _participant_by_seat.get(seat_index, {})
		var occupied := not str(participant.get("participant_id", "")).is_empty()
		var is_local := seat_index == local_seat_index
		var is_actor := seat_index == actor_seat_index
		var role_parts: Array[String] = []
		if is_local:
			role_parts.append("本地")
		if is_actor:
			role_parts.append("行动中")
		if bool(participant.get("is_bot", false)) and occupied:
			role_parts.append("机器人")
		_seat_position_labels[seat_index].text = _seat_position_text(seat_index, local_seat_index)
		_seat_name_labels[seat_index].text = str(participant.get("nickname", "等待参与者")) if occupied else "等待参与者"
		_seat_detail_labels[seat_index].text = (
			"分数 %d  ·  手牌 %d" % [int(participant.get("score", 0)), int(participant.get("hand_count", 0))]
			if occupied else "空席"
		)
		_seat_role_labels[seat_index].text = " · ".join(role_parts)
		var fill := COLOR_SURFACE_RAISED if occupied else COLOR_SURFACE
		var border := COLOR_GOLD if is_actor else (COLOR_GREEN if is_local else COLOR_BORDER)
		_seat_cards[seat_index].add_theme_stylebox_override("panel", _style_box(fill, border, 2 if is_actor else 1, 5))


func _refresh_history(rounds: Array[Dictionary]) -> void:
	for child in _history_list.get_children():
		child.free()
	if rounds.is_empty():
		var empty := _label("等待拼点揭晓", 12, COLOR_MUTED)
		empty.name = "HistoryEmpty"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_history_list.add_child(empty)
		_refresh_latest_contest({})
		return
	for round_data in rounds:
		var item := _build_history_item(round_data)
		_history_list.add_child(item)
	_refresh_latest_contest(rounds[rounds.size() - 1])


func _build_history_item(round_data: Dictionary) -> Control:
	var round_index := int(round_data.get("round_index", 0))
	var item := VBoxContainer.new()
	item.name = "ContestRound%d" % round_index
	item.add_theme_constant_override("separation", 2)
	var title := _label("第 %d 轮" % (round_index + 1), 12, COLOR_GOLD)
	title.clip_text = true
	item.add_child(title)
	var reveals: Variant = round_data.get("reveals", [])
	var reveal_text := _format_reveals(reveals)
	var winner_seat := int(round_data.get("winner_seat_index", -1))
	var summary := _label(reveal_text, 11, COLOR_MUTED)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_child(summary)
	var tied_seats: Variant = round_data.get("tied_seat_indexes", [])
	if tied_seats is Array and not tied_seats.is_empty():
		var tie_label := _label("平局：继续拼点", 11, COLOR_GOLD)
		tie_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.add_child(tie_label)
	if winner_seat >= 0:
		var winner := _label("胜者：%s" % _participant_name(winner_seat), 11, COLOR_TEXT)
		winner.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.add_child(winner)
	return item


func _refresh_latest_contest(round_data: Dictionary) -> void:
	for child in _contest_reveal_row.get_children():
		child.free()
	if round_data.is_empty():
		_contest_title_label.text = "最新拼点"
		_contest_detail_label.text = "等待公开翻牌"
		return
	var round_index := int(round_data.get("round_index", 0))
	_contest_title_label.text = "最新拼点 · 第 %d 轮" % (round_index + 1)
	var winner_seat := int(round_data.get("winner_seat_index", -1))
	var tied_seats: Variant = round_data.get("tied_seat_indexes", [])
	if winner_seat >= 0:
		_contest_detail_label.text = "胜者：%s" % _participant_name(winner_seat)
	elif tied_seats is Array and not tied_seats.is_empty():
		_contest_detail_label.text = "平局：%d 人继续拼点" % tied_seats.size()
	else:
		_contest_detail_label.text = "等待揭晓"
	var reveals: Variant = round_data.get("reveals", [])
	if reveals is Array:
		for reveal: Variant in reveals:
			if not reveal is Dictionary:
				continue
			var reveal_data: Dictionary = reveal
			var chip := _label(
				"%s\n%s" % [
					_participant_name(int(reveal_data.get("seat_index", -1))),
					_format_card(reveal_data.get("card", {})),
				],
				11,
				COLOR_TEXT
			)
			chip.custom_minimum_size = Vector2(58, 35)
			chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			chip.clip_text = true
			chip.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			_contest_reveal_row.add_child(chip)


func _refresh_hand() -> void:
	_clear_hand()
	var hand: Array[Dictionary] = _store.get_local_hand()
	_hand_title_label.text = "我的手牌（%d）" % hand.size()
	for index in range(hand.size()):
		var card := _build_hand_card(hand[index], index)
		_hand_row.add_child(card)
		_hand_cards.append(card)
	if hand.is_empty():
		var empty := _label("等待私有手牌", 12, COLOR_MUTED)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_hand_row.add_child(empty)
	call_deferred("_on_resized")


func _clear_hand() -> void:
	for child in _hand_row.get_children():
		child.free()
	_hand_cards.clear()
	_hand_title_label.text = "我的手牌（0）"


func _build_hand_card(card: Dictionary, index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "HandCard%d" % index
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE_RAISED, COLOR_BORDER, 1, 4))
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_theme_constant_override("margin_bottom", 4)
	panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	margin.add_child(column)
	var rank := _label(_rank_text(int(card.get("rank", 0))), 20, COLOR_TEXT)
	rank.name = "Rank"
	rank.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	rank.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(rank)
	var suit := _label(_suit_text(card.get("suit", "")), 15, _suit_color(card.get("suit", "")))
	suit.name = "Suit"
	suit.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	suit.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	column.add_child(suit)
	return panel


func _refresh_action_prompt(phase: String, actor_seat_index: int, local_seat_index: int) -> void:
	if phase == "point_contest":
		_action_prompt_label.text = "拼点进行中：所有公开翻牌后决定首位行动者"
	elif phase == "actor_play":
		if actor_seat_index == local_seat_index:
			_action_prompt_label.text = "轮到你：从手牌选择三张牌出牌"
		else:
			_action_prompt_label.text = "等待 %s 出牌" % _participant_name(actor_seat_index)
	elif phase == "claim_commit":
		if actor_seat_index == local_seat_index:
			_action_prompt_label.text = "本轮由你出牌：等待其他参与者抢牌"
		else:
			_action_prompt_label.text = "选择一张牌抢牌，或选择不抢"
	elif phase == "claim_reveal":
		_action_prompt_label.text = "抢牌选择同时揭晓中"
	elif phase == "award_discard":
		_action_prompt_label.text = "获得牌的参与者请选择一张原手牌弃置"
	elif phase == "final_commit":
		_action_prompt_label.text = "最终结算：选择两组不重叠的三张牌"
	elif phase == "final_reveal":
		_action_prompt_label.text = "最终选择已锁定，等待全部揭晓"
	elif phase == "finished":
		_action_prompt_label.text = "对局结束：查看最终排名"
	else:
		_action_prompt_label.text = "等待服务器状态"


func _on_resized() -> void:
	if _table_area == null:
		return
	var width := maxf(_table_area.size.x, 1.0)
	var height := maxf(_table_area.size.y, 1.0)
	var hand_height := minf(
		height,
		maxf(HAND_PANEL_HEIGHT, _hand_panel.get_combined_minimum_size().y)
	)
	var hand_y := maxf(0.0, height - hand_height)
	_hand_panel.position = Vector2(0, hand_y)
	_hand_panel.size = Vector2(width, hand_height)

	var stage_height := maxf(1.0, hand_y)
	var seat_width := minf(SEAT_WIDTH, maxf(150.0, (width - 36.0) * 0.28))
	var seat_height := SEAT_HEIGHT
	for seat_panel in _seat_cards:
		seat_height = maxf(seat_height, seat_panel.get_combined_minimum_size().y)
	var north_x := (width - seat_width) * 0.5
	var east_x := width - seat_width - 8.0
	var north_y := 7.0
	var side_y := clampf(
		(stage_height - seat_height) * 0.5,
		72.0,
		maxf(72.0, stage_height - seat_height - 8.0)
	)
	var local_y := maxf(8.0, stage_height - seat_height - 8.0)
	var local_index := _local_seat_index if _local_seat_index >= 0 else 0
	var seat_positions := {
		local_index: Vector2(north_x, local_y),
		posmod(local_index + 1, 4): Vector2(east_x, side_y),
		posmod(local_index + 2, 4): Vector2(north_x, north_y),
		posmod(local_index + 3, 4): Vector2(8.0, side_y),
	}
	for seat_index in range(4):
		_seat_cards[seat_index].position = seat_positions.get(seat_index, Vector2.ZERO)
		_seat_cards[seat_index].size = Vector2(seat_width, seat_height)

	# Four public reveals must fit in the center at the minimum supported width.
	var contest_width := minf(280.0, maxf(220.0, width * 0.42))
	var contest_height := maxf(76.0, _contest_panel.get_combined_minimum_size().y)
	_contest_panel.position = Vector2((width - contest_width) * 0.5, maxf(78.0, (stage_height - contest_height) * 0.46))
	_contest_panel.size = Vector2(contest_width, contest_height)


func _seat_position_text(seat_index: int, local_seat_index: int) -> String:
	if seat_index == local_seat_index:
		return "本地"
	var offset := posmod(seat_index - local_seat_index, 4)
	match offset:
		1:
			return "东"
		2:
			return "北"
		3:
			return "西"
	return "席位 %d" % (seat_index + 1)


func _participant_name(seat_index: int) -> String:
	if _participant_by_seat.has(seat_index):
		var participant: Dictionary = _participant_by_seat[seat_index]
		var nickname := str(participant.get("nickname", ""))
		if not nickname.is_empty():
			return nickname
	return "等待"


func _format_reveals(raw_reveals: Variant) -> String:
	if not raw_reveals is Array or raw_reveals.is_empty():
		return "未公开翻牌"
	var values: Array[String] = []
	for raw_reveal: Variant in raw_reveals:
		if raw_reveal is Dictionary:
			var reveal: Dictionary = raw_reveal
			values.append("%s %s" % [
				_participant_name(int(reveal.get("seat_index", -1))),
				_format_card(reveal.get("card", {})),
			])
	return "、".join(values)


func _format_card(raw_card: Variant) -> String:
	if not raw_card is Dictionary:
		return "--"
	var card: Dictionary = raw_card
	return "%s %s" % [_rank_text(int(card.get("rank", 0))), _suit_text(card.get("suit", ""))]


func _rank_text(rank: int) -> String:
	var value := rank
	match value:
		11:
			return "J"
		12:
			return "Q"
		13:
			return "K"
		14:
			return "A"
		_:
			return str(value) if value > 0 else "?"


func _suit_text(suit: Variant) -> String:
	match str(suit):
		"clubs":
			return "♣ 梅花"
		"spades":
			return "♠ 黑桃"
		"diamonds":
			return "♦ 方块"
		"hearts":
			return "♥ 红桃"
	return str(suit) if not str(suit).is_empty() else "?"


func _suit_color(suit: Variant) -> Color:
	return COLOR_HEARTS if str(suit) == "hearts" else (COLOR_DIAMONDS if str(suit) == "diamonds" else COLOR_BLACK_SUIT)


func _phase_text(phase: String) -> String:
	match phase:
		"point_contest":
			return "拼点"
		"actor_play":
			return "出牌"
		"claim_commit":
			return "抢牌"
		"claim_reveal":
			return "抢牌揭晓"
		"award_discard":
			return "弃牌"
		"final_commit":
			return "最终结算"
		"final_reveal":
			return "结算揭晓"
		"finished":
			return "已结束"
	return "同步中"


func _label(text: String, font_size: int, color: Color) -> Label:
	var result := Label.new()
	result.text = text
	result.add_theme_font_size_override("font_size", font_size)
	result.add_theme_color_override("font_color", color)
	return result


func _style_box(fill: Color, border: Color, border_width: int, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	return style
