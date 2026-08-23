extends Control
class_name MatchScreen

signal return_to_lobby_requested()

## Dense public match table.  The screen deliberately consumes a very small
## store protocol so that private data never has to pass through the scene.

const CombinationCatalog = preload("res://scripts/domain/combination_catalog.gd")
const CardRules = preload("res://scripts/domain/card_rules.gd")
const CardFaceCatalog = preload("res://scripts/presentation/card_face_catalog.gd")
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
const COLOR_ACQUIRED := Color("#4ea1ff")
const COLOR_HEARTS := Color("#ec7777")
const COLOR_DIAMONDS := Color("#ec7777")
const COLOR_BLACK_SUIT := Color("#d7dcdf")

const SEAT_WIDTH := 176.0
const SEAT_HEIGHT := 58.0
const HAND_PANEL_HEIGHT := 138.0
const CARD_WIDTH := 54.0
const CARD_HEIGHT := 84.0
const SEAT_ACTION_CARD_WIDTH := 54.0
const SEAT_ACTION_CARD_HEIGHT := 84.0
const DISCARD_STATUS_WIDTH := 120.0
const DISCARD_STATUS_HEIGHT := 30.0

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
var _played_panel: PanelContainer
var _played_title_label: Label
var _played_cards_row: HBoxContainer
var _played_summary_label: Label
var _claim_reveal_list: VBoxContainer
var _claim_discard_label: Label
var _hand_panel: PanelContainer
var _hand_title_label: Label
var _hand_row: HBoxContainer
var _action_bar: PanelContainer
var _action_prompt_label: Label
var _action_error_label: Label
var _play_preview_label: Label
var _hint_button: Button
var _play_button: Button
var _discard_button: Button
var _submit_claim_button: Button
var _pass_claim_button: Button
var _final_group_a_button: Button
var _final_group_b_button: Button
var _lock_final_button: Button
var _best_final_button: Button
var _return_to_lobby_button: Button

var _seat_cards: Array[PanelContainer] = []
var _seat_position_labels: Array[Label] = []
var _seat_name_labels: Array[Label] = []
var _seat_detail_labels: Array[Label] = []
var _seat_role_labels: Array[Label] = []
var _seat_action_panels: Array[PanelContainer] = []
var _hand_cards: Array[Button] = []
var _selected_card_ids: Array[String] = []
var _claim_choice_group := ButtonGroup.new()
var _selected_claim_card_id := ""
var _claim_submission_pending := false
var _discard_submission_pending := false
var _final_submission_pending := false
var _return_to_lobby_pending := false
var _final_group_mode := ButtonGroup.new()
var _active_final_group := 0
var _final_group_ids: Array = [[], []]
var _animated_collision_turns: Dictionary = {}
var _animated_reveal_keys: Dictionary = {}
var _reduced_motion := false
var _reveal_tween: Tween
var _match_identity := ""
var _last_phase := ""
var _last_action_id := -1

var _participant_by_seat: Dictionary = {}
var _local_seat_index := -1
var _time_source := func() -> float:
	return Time.get_unix_time_from_system() * 1000.0


func set_match_store(store: Object) -> void:
	if _store_override != store:
		_selected_card_ids.clear()
		_last_phase = ""
		_last_action_id = -1
	_store_override = store
	if is_inside_tree():
		_unbind_store()
		_store = store
		_bind_store()
		_refresh()


func set_time_source(source: Callable) -> void:
	if source.is_valid():
		_time_source = source
	_refresh_connection_label()


func set_reduced_motion(enabled: bool) -> void:
	_reduced_motion = enabled
	if enabled:
		_stop_reveal_motion()
	elif is_inside_tree():
		_refresh()


func _ready() -> void:
	_build_ui()
	_reduced_motion = bool(ProjectSettings.get_setting("application/accessibility/reduced_motion", false))
	_store = _store_override
	_bind_store()
	_refresh()
	_table_area.resized.connect(_on_resized)
	call_deferred("_on_resized")


func _process(_delta: float) -> void:
	_refresh_connection_label()


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
	if _store.has_signal("connection_changed"):
		_store.connection_changed.connect(_on_store_changed)
	if _store.has_signal("action_failed"):
		_store.action_failed.connect(_on_action_failed)


func _unbind_store() -> void:
	if _bound_store == null:
		return
	var callback := Callable(self, "_on_store_changed")
	if _bound_store.has_signal("state_changed") and _bound_store.is_connected("state_changed", callback):
		_bound_store.disconnect("state_changed", callback)
	if _bound_store.has_signal("private_state_changed") and _bound_store.is_connected("private_state_changed", callback):
		_bound_store.disconnect("private_state_changed", callback)
	if _bound_store.has_signal("connection_changed") and _bound_store.is_connected("connection_changed", callback):
		_bound_store.disconnect("connection_changed", callback)
	var error_callback := Callable(self, "_on_action_failed")
	if _bound_store.has_signal("action_failed") and _bound_store.is_connected("action_failed", error_callback):
		_bound_store.disconnect("action_failed", error_callback)
	_bound_store = null


func _on_store_changed(_first: Variant = null, _second: Variant = null, _third: Variant = null) -> void:
	_action_error_label.text = ""
	_action_error_label.tooltip_text = ""
	_refresh()


func _on_action_failed(code: String, message: String) -> void:
	var detail := message if not message.is_empty() else code
	_action_error_label.text = detail
	_action_error_label.tooltip_text = detail
	if _claim_submission_pending and _show_claim_controls():
		_claim_submission_pending = false
		_selected_claim_card_id = ""
		_refresh()
	elif _discard_submission_pending and _show_discard_controls():
		_discard_submission_pending = false
		_selected_card_ids.clear()
		_refresh()
	elif _final_submission_pending and _show_final_controls():
		_final_submission_pending = false
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
	_build_played_panel()

	for seat_index in range(4):
		_build_seat_card(seat_index)
		_build_seat_action_panel(seat_index)

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
	_hand_title_label = _label("我的手牌（5）", 13, COLOR_TEXT)
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
	_action_prompt_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_action_prompt_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_prompt_label.clip_text = true
	_action_prompt_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	var action_row := HBoxContainer.new()
	action_row.name = "ActionRow"
	action_row.add_theme_constant_override("separation", 8)
	action_margin.add_child(action_row)
	action_row.add_child(_action_prompt_label)
	var error_slot := Control.new()
	error_slot.name = "ActionErrorSlot"
	error_slot.custom_minimum_size = Vector2(210, 27)
	action_row.add_child(error_slot)
	_action_error_label = _label("", 11, COLOR_HEARTS)
	_action_error_label.name = "ActionErrorLabel"
	_action_error_label.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_action_error_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_action_error_label.clip_text = true
	_action_error_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	error_slot.add_child(_action_error_label)
	_hint_button = _build_compact_action_button("提示", 58.0)
	_hint_button.name = "HintButton"
	_hint_button.visible = false
	_hint_button.disabled = true
	_hint_button.pressed.connect(_on_hint_pressed)
	action_row.add_child(_hint_button)
	_play_preview_label = _label("", 12, COLOR_GOLD)
	_play_preview_label.name = "PlayPreviewLabel"
	_play_preview_label.custom_minimum_size = Vector2(108, 27)
	_play_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_play_preview_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_play_preview_label.visible = false
	action_row.add_child(_play_preview_label)
	_play_button = Button.new()
	_play_button.name = "PlayCardsButton"
	_play_button.text = "出牌"
	_play_button.custom_minimum_size = Vector2(82, 27)
	_play_button.disabled = true
	_play_button.add_theme_font_size_override("font_size", 13)
	_play_button.add_theme_color_override("font_color", COLOR_TEXT)
	_play_button.add_theme_stylebox_override("normal", _style_box(Color("#2b3334"), COLOR_BORDER, 1, 4))
	_play_button.add_theme_stylebox_override("hover", _style_box(Color("#34413d"), COLOR_GREEN, 1, 4))
	_play_button.add_theme_stylebox_override("pressed", _style_box(Color("#25392f"), COLOR_GREEN, 2, 4))
	_play_button.add_theme_stylebox_override("disabled", _style_box(Color("#202426"), COLOR_BORDER, 1, 4))
	_play_button.pressed.connect(_on_play_pressed)
	action_row.add_child(_play_button)
	_discard_button = Button.new()
	_discard_button.text = "弃牌"
	_discard_button.custom_minimum_size = Vector2(82, 27)
	_discard_button.visible = false
	_discard_button.disabled = true
	_discard_button.add_theme_font_size_override("font_size", 13)
	_discard_button.add_theme_color_override("font_color", COLOR_TEXT)
	_discard_button.add_theme_stylebox_override("normal", _style_box(Color("#2b3334"), COLOR_BORDER, 1, 4))
	_discard_button.add_theme_stylebox_override("hover", _style_box(Color("#34413d"), COLOR_GREEN, 1, 4))
	_discard_button.add_theme_stylebox_override("pressed", _style_box(Color("#30362f"), COLOR_GOLD, 2, 4))
	_discard_button.add_theme_stylebox_override("disabled", _style_box(Color("#202426"), COLOR_BORDER, 1, 4))
	_discard_button.pressed.connect(_on_discard_pressed)
	action_row.add_child(_discard_button)
	_submit_claim_button = Button.new()
	_submit_claim_button.name = "SubmitClaimButton"
	_submit_claim_button.text = "抢牌"
	_submit_claim_button.custom_minimum_size = Vector2(66, 27)
	_submit_claim_button.visible = false
	_submit_claim_button.disabled = true
	_submit_claim_button.add_theme_font_size_override("font_size", 13)
	_submit_claim_button.add_theme_color_override("font_color", COLOR_TEXT)
	_submit_claim_button.add_theme_stylebox_override("normal", _style_box(Color("#2b3334"), COLOR_BORDER, 1, 4))
	_submit_claim_button.add_theme_stylebox_override("hover", _style_box(Color("#34413d"), COLOR_GREEN, 1, 4))
	_submit_claim_button.add_theme_stylebox_override("pressed", _style_box(Color("#25392f"), COLOR_GREEN, 2, 4))
	_submit_claim_button.add_theme_stylebox_override("disabled", _style_box(Color("#202426"), COLOR_BORDER, 1, 4))
	_submit_claim_button.pressed.connect(_on_submit_claim_pressed)
	action_row.add_child(_submit_claim_button)
	_pass_claim_button = Button.new()
	_pass_claim_button.name = "PassClaimButton"
	_pass_claim_button.text = "不抢"
	_pass_claim_button.custom_minimum_size = Vector2(66, 27)
	_pass_claim_button.visible = false
	_pass_claim_button.add_theme_font_size_override("font_size", 13)
	_pass_claim_button.add_theme_color_override("font_color", COLOR_TEXT)
	_pass_claim_button.add_theme_stylebox_override("normal", _style_box(Color("#2b3334"), COLOR_BORDER, 1, 4))
	_pass_claim_button.add_theme_stylebox_override("hover", _style_box(Color("#34413d"), COLOR_GREEN, 1, 4))
	_pass_claim_button.add_theme_stylebox_override("pressed", _style_box(Color("#25392f"), COLOR_GREEN, 2, 4))
	_pass_claim_button.add_theme_stylebox_override("disabled", _style_box(Color("#202426"), COLOR_BORDER, 1, 4))
	_pass_claim_button.pressed.connect(_on_pass_claim_pressed)
	action_row.add_child(_pass_claim_button)
	_final_group_mode.allow_unpress = false
	_final_group_a_button = _build_compact_action_button("A 组", 54.0)
	_final_group_a_button.toggle_mode = true
	_final_group_a_button.button_group = _final_group_mode
	_final_group_a_button.button_pressed = true
	_final_group_a_button.toggled.connect(_on_final_group_mode_toggled.bind(0))
	action_row.add_child(_final_group_a_button)
	_final_group_b_button = _build_compact_action_button("B 组", 54.0)
	_final_group_b_button.toggle_mode = true
	_final_group_b_button.button_group = _final_group_mode
	_final_group_b_button.toggled.connect(_on_final_group_mode_toggled.bind(1))
	action_row.add_child(_final_group_b_button)
	_lock_final_button = _build_compact_action_button("锁定分组", 84.0)
	_lock_final_button.pressed.connect(_on_lock_final_pressed)
	action_row.add_child(_lock_final_button)
	_best_final_button = _build_compact_action_button("最佳并锁定", 100.0)
	_best_final_button.pressed.connect(_on_best_final_pressed)
	action_row.add_child(_best_final_button)
	_return_to_lobby_button = _build_compact_action_button("返回大厅", 88.0)
	_return_to_lobby_button.name = "ReturnToLobbyButton"
	_return_to_lobby_button.visible = false
	_return_to_lobby_button.pressed.connect(_on_return_to_lobby_pressed)
	action_row.add_child(_return_to_lobby_button)
	return _table_area


func _build_compact_action_button(text: String, minimum_width: float) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(minimum_width, 27)
	button.visible = false
	button.disabled = true
	button.add_theme_font_size_override("font_size", 12)
	button.add_theme_color_override("font_color", COLOR_TEXT)
	button.add_theme_stylebox_override("normal", _style_box(Color("#2b3334"), COLOR_BORDER, 1, 4))
	button.add_theme_stylebox_override("hover", _style_box(Color("#34413d"), COLOR_GREEN, 1, 4))
	button.add_theme_stylebox_override("pressed", _style_box(Color("#30362f"), COLOR_GOLD, 2, 4))
	button.add_theme_stylebox_override("disabled", _style_box(Color("#202426"), COLOR_BORDER, 1, 4))
	return button


func _build_played_panel() -> void:
	_played_panel = PanelContainer.new()
	_played_panel.name = "PlayedCombinationPanel"
	_played_panel.visible = false
	_played_panel.add_theme_stylebox_override("panel", _style_box(Color("#202925"), COLOR_GOLD, 2, 5))
	_table_area.add_child(_played_panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 10)
	margin.add_theme_constant_override("margin_top", 7)
	margin.add_theme_constant_override("margin_right", 10)
	margin.add_theme_constant_override("margin_bottom", 7)
	_played_panel.add_child(margin)
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	_played_title_label = _label("本回合公开出牌", 13, COLOR_GOLD)
	_played_title_label.name = "PlayedCombinationTitle"
	column.add_child(_played_title_label)
	_played_cards_row = HBoxContainer.new()
	_played_cards_row.name = "PlayedCardsRow"
	_played_cards_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_played_cards_row.add_theme_constant_override("separation", 6)
	column.add_child(_played_cards_row)
	_played_summary_label = _label("牌型：-- · 本次 0 分", 12, COLOR_TEXT)
	_played_summary_label.name = "PlayedCombinationSummary"
	_played_summary_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(_played_summary_label)
	_claim_reveal_list = VBoxContainer.new()
	_claim_reveal_list.name = "ClaimRevealList"
	_claim_reveal_list.visible = false
	_claim_reveal_list.add_theme_constant_override("separation", 2)
	column.add_child(_claim_reveal_list)
	_claim_discard_label = _label("", 11, COLOR_MUTED)
	_claim_discard_label.name = "ClaimDiscardedCards"
	_claim_discard_label.visible = false
	_claim_discard_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_claim_discard_label.clip_text = true
	_claim_discard_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	column.add_child(_claim_discard_label)


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
	role.custom_minimum_size = Vector2(84.0, 16.0)
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


func _build_seat_action_panel(seat_index: int) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.name = "SeatAction%d" % seat_index
	panel.custom_minimum_size = Vector2(SEAT_ACTION_CARD_WIDTH, SEAT_ACTION_CARD_HEIGHT)
	panel.visible = false
	panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE, COLOR_BORDER, 1, 5))
	_table_area.add_child(panel)
	_seat_action_panels.append(panel)
	return panel


func _refresh() -> void:
	if _store == null:
		_claim_submission_pending = false
		_discard_submission_pending = false
		_final_submission_pending = false
		_return_to_lobby_pending = false
		_selected_claim_card_id = ""
		_animated_collision_turns.clear()
		_animated_reveal_keys.clear()
		_stop_reveal_motion()
		_match_identity = ""
		_last_phase = ""
		_last_action_id = -1
		_reset_final_editor()
		_submit_claim_button.visible = false
		_submit_claim_button.disabled = true
		_pass_claim_button.visible = false
		_pass_claim_button.disabled = true
		_set_final_controls_visible(false)
		_hint_button.visible = false
		_play_preview_label.visible = false
		_return_to_lobby_button.visible = false
		_discard_button.visible = false
		_discard_button.disabled = true
		_participant_by_seat.clear()
		_phase_label.text = "阶段：同步中"
		_actor_label.text = "行动者：等待"
		_deck_label.text = "牌堆：--"
		_connection_label.text = "等待状态"
		_action_prompt_label.text = "等待服务器状态"
		_action_error_label.text = ""
		_action_error_label.tooltip_text = ""
		_refresh_seats(-1, -1)
		_refresh_history([], [], [], [], [])
		_refresh_played_combination("")
		_refresh_seat_actions("")
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
	var match_identity := "%s|%s" % [str(_store.room_id), str(_store.local_participant_id)]
	if match_identity != _match_identity:
		_animated_collision_turns.clear()
		_animated_reveal_keys.clear()
		_stop_reveal_motion()
		_reset_final_editor()
		_return_to_lobby_pending = false
		_last_phase = ""
		_last_action_id = -1
		_match_identity = match_identity
	var phase := str(_store.phase)
	var action_id := int(_store.get("action_id"))
	var actor_seat_index := int(_store.actor_seat_index)
	if phase == "final_commit" and (
		_last_phase != "final_commit"
		or _last_action_id != action_id
	):
		_reset_final_editor()
	if phase == "final_commit" and bool(_store.get("final_committed")):
		_final_submission_pending = false
		_apply_authoritative_final_groups()
	elif phase != "final_commit":
		_final_submission_pending = false
	if phase != "claim_commit" or actor_seat_index == local_seat_index:
		_claim_submission_pending = false
		_selected_claim_card_id = ""
	elif bool(_store.claim_committed):
		_claim_submission_pending = false
	if phase != "award_discard" or not _is_local_discard_pending():
		_discard_submission_pending = false
	_phase_label.text = "阶段：%s" % _phase_text(phase)
	_actor_label.text = (
		"行动者：无"
		if actor_seat_index < 0 and phase in ["final_commit", "final_reveal", "finished"]
		else "行动者：%s" % _participant_name(actor_seat_index)
	)
	_deck_label.text = "牌堆 %d · 封存 %d" % [
		int(_store.draw_pile_count),
		int(_store.get("sealed_card_count")),
	]
	_refresh_connection_label()
	_refresh_seats(local_seat_index, actor_seat_index)
	var play_events: Array[Dictionary] = []
	if _store.has_method("get_play_events"):
		play_events = _store.get_play_events()
	var claim_events: Array[Dictionary] = []
	if _store.has_method("get_claim_events"):
		claim_events = _store.get_claim_events()
	var discard_events: Array[Dictionary] = []
	if _store.has_method("get_discard_events"):
		discard_events = _store.get_discard_events()
	var final_events: Array[Dictionary] = []
	if _store.has_method("get_final_events"):
		final_events = _store.get_final_events()
	_refresh_history(
		_store.get_contest_rounds(),
		play_events,
		claim_events,
		discard_events,
		final_events
	)
	_refresh_played_combination(phase)
	_refresh_seat_actions(phase)
	_refresh_hand()
	_refresh_action_prompt(phase, actor_seat_index, local_seat_index)
	_last_phase = phase
	_last_action_id = action_id


func _reset_final_editor() -> void:
	_final_submission_pending = false
	_active_final_group = 0
	_final_group_ids = [[], []]
	if _final_group_a_button != null:
		_final_group_a_button.set_pressed_no_signal(true)
	if _final_group_b_button != null:
		_final_group_b_button.set_pressed_no_signal(false)


func _apply_authoritative_final_groups() -> void:
	if _store == null or not _store.has_method("get_final_groups"):
		return
	var authoritative_groups: Array = _store.get_final_groups()
	if _is_valid_final_groups(authoritative_groups):
		_final_group_ids = authoritative_groups.duplicate(true)


func _is_valid_final_groups(groups: Array) -> bool:
	if groups.size() != 2:
		return false
	var selected_card_ids: Dictionary = {}
	for raw_group: Variant in groups:
		if not raw_group is Array or raw_group.size() != 3:
			return false
		for raw_card_id: Variant in raw_group:
			var card_id := str(raw_card_id)
			if card_id.is_empty() or selected_card_ids.has(card_id):
				return false
			selected_card_ids[card_id] = true
	return true


func _set_final_controls_visible(visible: bool) -> void:
	for button in [
		_final_group_a_button,
		_final_group_b_button,
		_lock_final_button,
		_best_final_button,
	]:
		if button != null:
			button.visible = visible


func _find_local_seat_index() -> int:
	var local_id := str(_store.local_participant_id)
	for seat_index in _participant_by_seat.keys():
		var participant: Dictionary = _participant_by_seat[seat_index]
		if str(participant.get("participant_id", "")) == local_id:
			return int(seat_index)
	return -1


func _refresh_seats(local_seat_index: int, actor_seat_index: int) -> void:
	var winner_seat_indexes: Array[int] = []
	if _store != null and _store.has_method("get_winner_seat_indexes"):
		winner_seat_indexes = _store.get_winner_seat_indexes()
	for seat_index in range(4):
		_seat_cards[seat_index].visible = true
		var participant: Dictionary = _participant_by_seat.get(seat_index, {})
		var occupied := not str(participant.get("participant_id", "")).is_empty()
		var is_local := seat_index == local_seat_index
		var is_actor := seat_index == actor_seat_index
		var is_winner := winner_seat_indexes.has(seat_index)
		var role_parts: Array[String] = []
		var is_bot := bool(participant.get("is_bot", false))
		var is_connected := bool(participant.get("is_connected", true))
		var is_terminal_phase := _store != null and str(_store.get("phase")) in ["final_reveal", "finished"]
		if is_winner and is_terminal_phase:
			# The settlement role is the primary signal; keep it whole in compact seat headers.
			role_parts.append("共同胜者" if winner_seat_indexes.size() > 1 else "胜者")
		else:
			if is_local:
				role_parts.append("本地")
			if is_actor:
				role_parts.append("行动中")
			if is_bot and occupied:
				role_parts.append("机器人")
			elif occupied and not is_connected:
				role_parts.append("断线")
			if is_winner:
				role_parts.append("共同胜者" if winner_seat_indexes.size() > 1 else "胜者")
		_seat_position_labels[seat_index].text = _seat_position_text(seat_index, local_seat_index)
		_seat_name_labels[seat_index].text = str(participant.get("nickname", "等待参与者")) if occupied else "等待参与者"
		var detail_prefix := "机器人 · " if is_terminal_phase and is_bot else ""
		_seat_detail_labels[seat_index].text = (
			"%s分数 %d  ·  手牌 %d" % [detail_prefix, int(participant.get("score", 0)), int(participant.get("hand_count", 0))]
			if occupied else "空席"
		)
		_seat_role_labels[seat_index].text = " · ".join(role_parts)
		var fill := COLOR_SURFACE_RAISED if occupied else COLOR_SURFACE
		var border := COLOR_GOLD if is_actor or is_winner else (COLOR_GREEN if is_local else COLOR_BORDER)
		_seat_cards[seat_index].add_theme_stylebox_override("panel", _style_box(fill, border, 2 if is_actor else 1, 5))


func _refresh_history(
	rounds: Array[Dictionary],
	play_events: Array[Dictionary],
	claim_events: Array[Dictionary],
	discard_events: Array[Dictionary],
	final_events: Array[Dictionary]
) -> void:
	for child in _history_list.get_children():
		child.free()
	if (
		rounds.is_empty()
		and play_events.is_empty()
		and claim_events.is_empty()
		and discard_events.is_empty()
		and final_events.is_empty()
	):
		var empty := _label("等待公开事件", 12, COLOR_MUTED)
		empty.name = "HistoryEmpty"
		empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_history_list.add_child(empty)
		_refresh_latest_contest({})
		return
	for round_data in rounds:
		var item := _build_history_item(round_data)
		_history_list.add_child(item)
	var timeline: Array[Dictionary] = []
	for play_event in play_events:
		timeline.append({
			"turn_number": int(play_event.get("turn_number", 0)),
			"kind_order": 0,
			"data": play_event,
		})
	for claim_event in claim_events:
		timeline.append({
			"turn_number": int(claim_event.get("turn_number", 0)),
			"kind_order": 1,
			"data": claim_event,
		})
	for discard_event in discard_events:
		timeline.append({
			"turn_number": int(discard_event.get("turn_number", 0)),
			"kind_order": 2,
			"data": discard_event,
		})
	timeline.sort_custom(_public_history_entry_before)
	for entry in timeline:
		var data: Dictionary = entry["data"]
		match int(entry["kind_order"]):
			0:
				_history_list.add_child(_build_play_history_item(data))
			1:
				_history_list.add_child(_build_claim_history_item(data))
			_:
				_history_list.add_child(_build_discard_history_item(data))
	for final_event in final_events:
		_history_list.add_child(_build_final_history_item(final_event))
	_refresh_latest_contest(rounds[rounds.size() - 1] if not rounds.is_empty() else {})


func _public_history_entry_before(left: Dictionary, right: Dictionary) -> bool:
	var left_turn := int(left.get("turn_number", 0))
	var right_turn := int(right.get("turn_number", 0))
	if left_turn != right_turn:
		return left_turn < right_turn
	return int(left.get("kind_order", 0)) < int(right.get("kind_order", 0))


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


func _build_play_history_item(play_event: Dictionary) -> Control:
	var turn_number := int(play_event.get("turn_number", 0))
	var actor_seat_index := int(play_event.get("actor_seat_index", -1))
	var item := VBoxContainer.new()
	item.name = "PlayEvent%d" % turn_number
	item.add_theme_constant_override("separation", 2)
	var title := _label(
		"第 %d 回合 · %s 出牌" % [turn_number, _participant_name(actor_seat_index)],
		12,
		COLOR_GOLD
	)
	title.clip_text = true
	item.add_child(title)
	var summary := _label(
		"%s · %d 分" % [
			_combination_text(str(play_event.get("category", ""))),
			int(play_event.get("score", 0)),
		],
		11,
		COLOR_TEXT
	)
	item.add_child(summary)
	var raw_cards: Variant = play_event.get("cards", [])
	if raw_cards is Array:
		var card_values: Array[String] = []
		for raw_card: Variant in raw_cards:
			card_values.append(_format_card(raw_card))
		var cards := _label("、".join(card_values), 11, COLOR_MUTED)
		cards.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.add_child(cards)
	return item


func _build_claim_history_item(claim_event: Dictionary) -> Control:
	var turn_number := int(claim_event.get("turn_number", 0))
	var item := VBoxContainer.new()
	item.name = "ClaimEvent%d" % turn_number
	item.add_theme_constant_override("separation", 2)
	var title := _label("第 %d 回合 · 抢牌揭晓" % turn_number, 12, COLOR_GOLD)
	title.clip_text = true
	item.add_child(title)
	var card_by_id := _claim_event_cards_by_id(claim_event)
	var awards_by_seat := _claim_event_awards_by_seat(claim_event)
	var raw_claims: Variant = claim_event.get("claims", [])
	if raw_claims is Array:
		for raw_claim: Variant in raw_claims:
			if not raw_claim is Dictionary:
				continue
			var detail := _label(
				_claim_outcome_text(raw_claim, card_by_id, awards_by_seat),
				11,
				COLOR_TEXT
			)
			detail.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			item.add_child(detail)
	var discarded_text := _discarded_cards_text(claim_event.get("discarded_cards", []))
	if not discarded_text.is_empty():
		var discarded := _label("弃置：%s" % discarded_text, 11, COLOR_MUTED)
		discarded.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		item.add_child(discarded)
	return item


func _build_discard_history_item(discard_event: Dictionary) -> Control:
	var turn_number := int(discard_event.get("turn_number", 0))
	var seat_index := int(discard_event.get("seat_index", -1))
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", 2)
	var title := _label(
		"第 %d 回合 · %s 弃置" % [turn_number, _participant_name(seat_index)],
		12,
		COLOR_GOLD
	)
	title.clip_text = true
	item.add_child(title)
	var card := _label(_format_card(discard_event.get("card", {})), 11, COLOR_MUTED)
	card.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_child(card)
	return item


func _build_final_history_item(final_event: Dictionary) -> Control:
	var item := VBoxContainer.new()
	item.add_theme_constant_override("separation", 2)
	var title := _label("最终结算", 12, COLOR_GOLD)
	item.add_child(title)
	var winners := _winner_names(final_event.get("winner_seat_indexes", []))
	var winner_label := _label(
		("共同胜者：%s" if winners.size() > 1 else "胜者：%s") % "、".join(winners),
		11,
		COLOR_TEXT
	)
	winner_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	item.add_child(winner_label)
	var raw_results: Variant = final_event.get("results", [])
	if raw_results is Array:
		for raw_result: Variant in raw_results:
			if not raw_result is Dictionary:
				continue
			var result_label := _label(
				"%s · 结算 +%d" % [
					_participant_name(int(raw_result.get("seat_index", -1))),
					int(raw_result.get("total_score", 0)),
				],
				10,
				COLOR_MUTED
			)
			result_label.clip_text = true
			item.add_child(result_label)
	return item


func _refresh_latest_contest(round_data: Dictionary) -> void:
	_contest_title_label.add_theme_font_size_override("font_size", 13)
	_contest_detail_label.visible = true
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
			var chip := VBoxContainer.new()
			chip.custom_minimum_size = Vector2(54, 78)
			chip.add_theme_constant_override("separation", 2)
			var participant := _label(
				_participant_name(int(reveal_data.get("seat_index", -1))),
				10,
				COLOR_TEXT
			)
			participant.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			participant.clip_text = true
			participant.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			chip.add_child(participant)
			var reveal_card: Variant = reveal_data.get("card", {})
			if reveal_card is Dictionary:
				chip.add_child(_build_card_face(reveal_card, Vector2(38, 59)))
			_contest_reveal_row.add_child(chip)


func _refresh_played_combination(phase: String) -> void:
	for child in _played_cards_row.get_children():
		child.free()
	for child in _claim_reveal_list.get_children():
		child.free()
	var cards: Array[Dictionary] = []
	if _store != null and _store.has_method("get_played_cards"):
		cards = _store.get_played_cards()
	var claim_event := _current_claim_event()
	var final_results: Array[Dictionary] = []
	if _store != null and _store.has_method("get_final_results"):
		final_results = _store.get_final_results()
	var show_played := phase == "claim_commit" and cards.size() == 3
	var show_claim_reveal := phase == "claim_reveal" and not claim_event.is_empty()
	var show_final_settlement := phase in ["final_reveal", "finished"] and not final_results.is_empty()
	_played_panel.visible = show_played or show_final_settlement
	_contest_panel.visible = (
		not _played_panel.visible
		and phase not in ["play_reveal", "claim_reveal"]
	)
	_played_cards_row.visible = show_played
	_played_summary_label.visible = show_played or show_final_settlement
	_claim_reveal_list.visible = show_claim_reveal or show_final_settlement
	_claim_discard_label.visible = show_claim_reveal
	if phase == "actor_play":
		_set_contest_status("请选择 3 张牌打出", "")
	if not show_played and not show_claim_reveal and not show_final_settlement:
		_played_title_label.text = "本回合公开出牌"
		_played_summary_label.text = "牌型：-- · 本次 0 分"
		_claim_discard_label.text = ""
		return
	if show_final_settlement:
		_refresh_final_settlement(phase, final_results)
		call_deferred("_on_resized")
		return
	if show_claim_reveal:
		_refresh_claim_reveal(claim_event)
		call_deferred("_on_resized")
		return
	_played_title_label.text = "第 %d 回合 · 公开出牌" % int(_store.turn_number)
	_played_summary_label.text = "牌型：%s · 本次 %d 分" % [
		_combination_text(str(_store.played_category)),
		int(_store.played_score),
	]
	var show_claim_controls := _show_claim_controls()
	var can_choose_claim := _can_choose_claim()
	for index in range(cards.size()):
		var chip: Control
		if show_claim_controls:
			var choice := Button.new()
			choice.name = "ClaimCard%d" % index
			# Keep the semantic button name for keyboard/test discovery; the visual is the texture child.
			choice.text = _format_card(cards[index])
			choice.toggle_mode = true
			choice.button_group = _claim_choice_group
			choice.disabled = not can_choose_claim
			choice.custom_minimum_size = Vector2(65, 101)
			choice.add_theme_font_size_override("font_size", 1)
			for color_name in ["font_color", "font_hover_color", "font_pressed_color", "font_disabled_color"]:
				choice.add_theme_color_override(color_name, Color.TRANSPARENT)
			choice.add_theme_stylebox_override("normal", _style_box(COLOR_SURFACE_RAISED, COLOR_BORDER, 1, 4))
			choice.add_theme_stylebox_override("hover", _style_box(Color("#29332f"), COLOR_GREEN, 1, 4))
			choice.add_theme_stylebox_override("pressed", _style_box(Color("#30362f"), COLOR_GOLD, 3, 4))
			choice.add_theme_stylebox_override("disabled", _style_box(COLOR_SURFACE, COLOR_BORDER, 1, 4))
			_add_card_face_to_button(choice, cards[index])
			choice.toggled.connect(_on_claim_card_toggled.bind(str(cards[index].get("id", "")), choice))
			if str(cards[index].get("id", "")) == _selected_claim_card_id:
				choice.set_pressed_no_signal(true)
			chip = choice
		else:
			var read_only := PanelContainer.new()
			read_only.name = "PlayedCard%d" % index
			read_only.custom_minimum_size = Vector2(65, 101)
			read_only.add_theme_stylebox_override("panel", _style_box(COLOR_SURFACE_RAISED, COLOR_BORDER, 1, 4))
			var face := _build_card_face(cards[index], Vector2.ZERO)
			face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
			face.offset_left = 2
			face.offset_top = 2
			face.offset_right = -2
			face.offset_bottom = -2
			read_only.add_child(face)
			chip = read_only
		_played_cards_row.add_child(chip)
	call_deferred("_on_resized")


func _add_card_face_to_button(button: Button, card: Dictionary) -> void:
	button.clip_contents = true
	var face := _build_card_face(card, Vector2.ZERO)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.offset_left = 2
	face.offset_top = 2
	face.offset_right = -2
	face.offset_bottom = -2
	button.add_child(face)
	var accessible_name := _label(_format_card(card), 1, Color.TRANSPARENT)
	accessible_name.name = "AccessibleCardName"
	accessible_name.visible = false
	button.add_child(accessible_name)
	button.tooltip_text = _format_card(card)


func _refresh_seat_actions(phase: String) -> void:
	for panel in _seat_action_panels:
		panel.visible = false
		for child in panel.get_children():
			child.free()
	if _store == null:
		return
	if phase == "play_reveal":
		var play_event := _current_play_event()
		var cards: Array[Dictionary] = []
		var actor_seat_index := int(_store.actor_seat_index)
		var category := str(_store.played_category)
		var score := int(_store.played_score)
		if not play_event.is_empty():
			actor_seat_index = int(play_event.get("actor_seat_index", actor_seat_index))
			category = str(play_event.get("category", category))
			score = int(play_event.get("score", score))
			cards = _dictionary_cards(play_event.get("cards", []))
		elif _store.has_method("get_played_cards"):
			cards = _store.get_played_cards()
		_set_seat_action(
			actor_seat_index,
			"出牌 · %s · +%d 分" % [_combination_text(category), score],
			cards,
			COLOR_GOLD
		)
		_set_contest_status("出牌公示", "查看行动者本回合出的牌")
		return
	var claim_event := _current_claim_event()
	var awards_by_seat := _claim_event_awards_by_seat(claim_event)
	if phase == "claim_reveal":
		for raw_seat_index: Variant in awards_by_seat.keys():
			var seat_index := int(raw_seat_index)
			var award: Dictionary = awards_by_seat[raw_seat_index]
			var card: Variant = award.get("card", {})
			if card is Dictionary:
				_set_seat_action(
					seat_index,
					"抢牌获得",
					[card],
					COLOR_ACQUIRED,
					str(award.get("source", "")) == "collision"
				)
		return
	if phase not in ["award_discard", "discard_reveal"]:
		return
	var discarded_by_seat: Dictionary = {}
	if _store.has_method("get_discard_events"):
		for discard_event: Dictionary in _store.get_discard_events():
			if int(discard_event.get("turn_number", 0)) == int(_store.turn_number):
				discarded_by_seat[int(discard_event.get("seat_index", -1))] = discard_event.get("card", {})
	for raw_seat_index: Variant in awards_by_seat.keys():
		var seat_index := int(raw_seat_index)
		if discarded_by_seat.has(seat_index):
			var discarded_card: Variant = discarded_by_seat[seat_index]
			if discarded_card is Dictionary:
				_set_seat_action(seat_index, "弃牌", [discarded_card], COLOR_GOLD)
		else:
			var award: Dictionary = awards_by_seat[raw_seat_index]
			var awarded_card: Variant = award.get("card", {})
			if awarded_card is Dictionary:
				_set_seat_action(seat_index, "抢牌获得", [awarded_card], COLOR_ACQUIRED)
	for raw_seat_index: Variant in discarded_by_seat.keys():
		var seat_index := int(raw_seat_index)
		if awards_by_seat.has(seat_index):
			continue
		var discarded_card: Variant = discarded_by_seat[raw_seat_index]
		if discarded_card is Dictionary:
			_set_seat_action(seat_index, "弃牌", [discarded_card], COLOR_GOLD)
	if phase == "discard_reveal":
		_set_contest_status("弃牌完成", "")
	elif _is_local_discard_pending():
		_set_contest_status("你需要弃置一张牌", "")
	else:
		_set_contest_status("等待其他玩家弃牌", "")


func _set_contest_status(title: String, detail: String) -> void:
	for child in _contest_reveal_row.get_children():
		child.free()
	_contest_title_label.text = title
	_contest_title_label.add_theme_font_size_override("font_size", 11)
	_contest_detail_label.text = detail
	_contest_detail_label.visible = not detail.is_empty()


func _set_seat_action(
	seat_index: int,
	title: String,
	cards: Array,
	border_color: Color,
	is_collision := false
) -> void:
	if seat_index < 0 or seat_index >= _seat_action_panels.size() or cards.is_empty():
		return
	var panel := _seat_action_panels[seat_index]
	panel.custom_minimum_size = Vector2(
		SEAT_ACTION_CARD_WIDTH * cards.size(),
		SEAT_ACTION_CARD_HEIGHT
	)
	var panel_style := _style_box(Color.TRANSPARENT, border_color, 2, 4)
	panel_style.content_margin_left = 0
	panel_style.content_margin_top = 0
	panel_style.content_margin_right = 0
	panel_style.content_margin_bottom = 0
	panel.add_theme_stylebox_override("panel", panel_style)
	var content := Control.new()
	content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	panel.add_child(content)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.add_theme_constant_override("separation", 0)
	content.add_child(row)
	for raw_card: Variant in cards:
		if raw_card is Dictionary:
			var face := _build_card_face(
				raw_card,
				Vector2(SEAT_ACTION_CARD_WIDTH, SEAT_ACTION_CARD_HEIGHT)
			)
			face.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			face.size_flags_vertical = Control.SIZE_EXPAND_FILL
			row.add_child(face)
	var title_label := _label(title, 9, border_color)
	title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title_label.clip_text = true
	title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title_label.add_theme_stylebox_override(
		"normal",
		_style_box(Color(0.05, 0.06, 0.07, 0.9), Color.TRANSPARENT, 0, 0)
	)
	title_label.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title_label.offset_left = 2
	title_label.offset_top = 2
	title_label.offset_right = -2
	title_label.offset_bottom = 18
	content.add_child(title_label)
	var outline := Panel.new()
	outline.mouse_filter = Control.MOUSE_FILTER_IGNORE
	outline.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	outline.add_theme_stylebox_override(
		"panel",
		_style_box(Color.TRANSPARENT, border_color, 2, 4)
	)
	content.add_child(outline)
	panel.visible = true
	_animate_seat_action(panel, seat_index, title, is_collision)


func _animate_seat_action(
	panel: PanelContainer,
	seat_index: int,
	title: String,
	is_collision: bool
) -> void:
	var key := "seat|%s|%d|%d|%s" % [str(_store.phase), int(_store.turn_number), seat_index, title]
	if _reduced_motion or _animated_reveal_keys.has(key):
		panel.modulate = Color.WHITE
		panel.scale = Vector2.ONE
		return
	_animated_reveal_keys[key] = true
	panel.modulate = Color(1.0, 1.0, 1.0, 0.72)
	panel.scale = Vector2(0.96, 1.0) if is_collision else Vector2.ONE
	var tween := create_tween()
	tween.set_parallel(true)
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(panel, "modulate", Color.WHITE, 0.22)
	if is_collision:
		tween.tween_property(panel, "scale", Vector2.ONE, 0.18)


func _current_play_event() -> Dictionary:
	if _store == null or not _store.has_method("get_play_events"):
		return {}
	var play_events: Array[Dictionary] = _store.get_play_events()
	for index in range(play_events.size() - 1, -1, -1):
		if int(play_events[index].get("turn_number", 0)) == int(_store.turn_number):
			return play_events[index]
	return play_events[play_events.size() - 1] if not play_events.is_empty() else {}


func _dictionary_cards(raw_cards: Variant) -> Array[Dictionary]:
	var cards: Array[Dictionary] = []
	if raw_cards is Array:
		for raw_card: Variant in raw_cards:
			if raw_card is Dictionary:
				cards.append(raw_card)
	return cards


func _refresh_final_settlement(phase: String, final_results: Array[Dictionary]) -> void:
	var winner_seat_indexes: Array[int] = []
	if _store.has_method("get_winner_seat_indexes"):
		winner_seat_indexes = _store.get_winner_seat_indexes()
	var winner_names := _winner_names(winner_seat_indexes)
	_played_title_label.text = (
		"对局结束 · 最终排名"
		if phase == "finished"
		else "最终结算 · 统一揭晓"
	)
	_played_summary_label.text = (
		("共同胜者：%s" if winner_names.size() > 1 else "胜者：%s")
		% "、".join(winner_names)
	)
	_claim_discard_label.text = ""
	var ordered_results := final_results.duplicate(true)
	if phase == "finished":
		ordered_results.sort_custom(_final_result_rank_before)
	else:
		ordered_results.sort_custom(_final_result_seat_before)
	var display_rank := 0
	var previous_score: Variant = null
	for result_index in range(ordered_results.size()):
		var result: Dictionary = ordered_results[result_index]
		var seat_index := int(result.get("seat_index", -1))
		var participant_score := _participant_score(seat_index)
		var is_winner := winner_seat_indexes.has(seat_index)
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", 0)
		_claim_reveal_list.add_child(row)
		var heading_text := "%s · 结算 +%d · 总分 %d · 手牌 %d" % [
			_settlement_participant_name(seat_index),
			int(result.get("total_score", 0)),
			_participant_score(seat_index),
			_participant_hand_count(seat_index),
		]
		if phase == "finished":
			if previous_score == null or participant_score != int(previous_score):
				display_rank = result_index + 1
			previous_score = participant_score
			heading_text = "第 %d 名 · %s · 总分 %d%s · 手牌 %d" % [
				display_rank,
				_settlement_participant_name(seat_index),
				participant_score,
				(
					" · 共同胜者"
					if is_winner and winner_seat_indexes.size() > 1
					else (" · 胜者" if is_winner else "")
				),
				_participant_hand_count(seat_index),
			]
		var heading := _label(heading_text, 11, COLOR_GOLD if is_winner else COLOR_TEXT)
		heading.custom_minimum_size.y = 15
		heading.clip_text = true
		heading.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		heading.tooltip_text = heading_text
		row.add_child(heading)
		var raw_groups: Variant = result.get("groups", [])
		if raw_groups is Array:
			for group_index in range(raw_groups.size()):
				var raw_group: Variant = raw_groups[group_index]
				if not raw_group is Dictionary:
					continue
				var group_text := _final_group_summary(group_index, raw_group)
				var group_label := _label(group_text, 10, COLOR_MUTED)
				group_label.custom_minimum_size.y = 13
				group_label.clip_text = true
				group_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
				group_label.tooltip_text = group_text
				row.add_child(group_label)
	_play_reveal_motion("final|%s|%d" % [phase, int(_store.get("action_id"))])


func _final_group_summary(_group_index: int, group: Dictionary) -> String:
	var card_values: Array[String] = []
	var raw_cards: Variant = group.get("cards", [])
	if raw_cards is Array:
		for raw_card: Variant in raw_cards:
			if raw_card is Dictionary:
				card_values.append(_compact_card(raw_card))
	return "%s · +%d 分 · %s" % [
		_combination_text(str(group.get("category", ""))),
		int(group.get("score", 0)),
		" ".join(card_values),
	]


func _final_result_seat_before(left: Dictionary, right: Dictionary) -> bool:
	return int(left.get("seat_index", -1)) < int(right.get("seat_index", -1))


func _final_result_rank_before(left: Dictionary, right: Dictionary) -> bool:
	var left_seat_index := int(left.get("seat_index", -1))
	var right_seat_index := int(right.get("seat_index", -1))
	var left_score := _participant_score(left_seat_index)
	var right_score := _participant_score(right_seat_index)
	if left_score == right_score:
		return left_seat_index < right_seat_index
	return left_score > right_score


func _participant_score(seat_index: int) -> int:
	var participant: Dictionary = _participant_by_seat.get(seat_index, {})
	return int(participant.get("score", 0))


func _participant_hand_count(seat_index: int) -> int:
	var participant: Dictionary = _participant_by_seat.get(seat_index, {})
	return int(participant.get("hand_count", 0))


func _winner_names(raw_seat_indexes: Variant) -> Array[String]:
	var names: Array[String] = []
	if not raw_seat_indexes is Array:
		return names
	for raw_seat_index: Variant in raw_seat_indexes:
		names.append(_settlement_participant_name(int(raw_seat_index)))
	return names


func _current_claim_event() -> Dictionary:
	if _store == null or not _store.has_method("get_claim_events"):
		return {}
	var claim_events: Array[Dictionary] = _store.get_claim_events()
	for index in range(claim_events.size() - 1, -1, -1):
		if int(claim_events[index].get("turn_number", 0)) == int(_store.turn_number):
			return claim_events[index]
	return claim_events[claim_events.size() - 1] if not claim_events.is_empty() else {}


func _refresh_claim_reveal(claim_event: Dictionary) -> void:
	var turn_number := int(claim_event.get("turn_number", 0))
	_played_title_label.text = "第 %d 回合 · 抢牌同时揭晓" % turn_number
	var raw_claims: Variant = claim_event.get("claims", [])
	var claim_count: int = raw_claims.size() if raw_claims is Array else 0
	_played_summary_label.text = ""
	var card_by_id := _claim_event_cards_by_id(claim_event)
	var awards_by_seat := _claim_event_awards_by_seat(claim_event)
	var animate_collisions := not _animated_collision_turns.has(turn_number)
	var collision_animated := false
	if raw_claims is Array:
		for raw_claim: Variant in raw_claims:
			if not raw_claim is Dictionary:
				continue
			var seat_index := int(raw_claim.get("seat_index", -1))
			var outcome := _label(
				_claim_outcome_text(raw_claim, card_by_id, awards_by_seat),
				11,
				COLOR_TEXT
			)
			outcome.name = "ClaimOutcomeSeat%d" % seat_index
			outcome.custom_minimum_size.y = 20
			outcome.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			outcome.clip_text = true
			outcome.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
			outcome.tooltip_text = outcome.text
			_claim_reveal_list.add_child(outcome)
			var award: Dictionary = awards_by_seat.get(seat_index, {})
			if animate_collisions and str(award.get("source", "")) == "collision":
				if _reduced_motion:
					outcome.scale = Vector2.ONE
				else:
					outcome.scale = Vector2(0.96, 1.0)
					call_deferred("_animate_collision_outcome", outcome)
				collision_animated = true
	if collision_animated:
		_animated_collision_turns[turn_number] = true
	_play_reveal_motion("claim|%d" % turn_number)
	_claim_discard_label.text = (
		"%d/%d 已揭晓" % [claim_count, 3]
		if _discarded_cards_text(claim_event.get("discarded_cards", [])).is_empty()
		else "弃置：%s" % _discarded_cards_text(claim_event.get("discarded_cards", []))
	)


func _animate_collision_outcome(outcome: Label) -> void:
	if _reduced_motion or not is_instance_valid(outcome):
		if is_instance_valid(outcome):
			outcome.scale = Vector2.ONE
		return
	var tween := create_tween()
	tween.set_trans(Tween.TRANS_QUAD)
	tween.set_ease(Tween.EASE_OUT)
	tween.tween_property(outcome, "scale", Vector2.ONE, 0.18)


func _play_reveal_motion(key: String) -> void:
	if _played_panel == null:
		return
	if _reduced_motion or _animated_reveal_keys.has(key):
		_played_panel.modulate = Color.WHITE
		return
	_animated_reveal_keys[key] = true
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_played_panel.modulate = Color(1.0, 1.0, 1.0, 0.72)
	_reveal_tween = create_tween()
	_reveal_tween.set_trans(Tween.TRANS_QUAD)
	_reveal_tween.set_ease(Tween.EASE_OUT)
	_reveal_tween.tween_property(_played_panel, "modulate", Color.WHITE, 0.22)


func _stop_reveal_motion() -> void:
	if _reveal_tween != null and _reveal_tween.is_valid():
		_reveal_tween.kill()
	_reveal_tween = null
	if _played_panel != null:
		_played_panel.modulate = Color.WHITE
	if _claim_reveal_list != null:
		for child in _claim_reveal_list.get_children():
			if child is Control:
				(child as Control).scale = Vector2.ONE


func _claim_event_cards_by_id(claim_event: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var raw_awards: Variant = claim_event.get("awards", [])
	if raw_awards is Array:
		for raw_award: Variant in raw_awards:
			if raw_award is Dictionary:
				var card: Variant = raw_award.get("card", {})
				if card is Dictionary and not str(card.get("id", "")).is_empty():
					result[str(card.get("id", ""))] = card
	var raw_discarded: Variant = claim_event.get("discarded_cards", [])
	if raw_discarded is Array:
		for raw_card: Variant in raw_discarded:
			if raw_card is Dictionary and not str(raw_card.get("id", "")).is_empty():
				result[str(raw_card.get("id", ""))] = raw_card
	return result


func _claim_event_awards_by_seat(claim_event: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var raw_awards: Variant = claim_event.get("awards", [])
	if raw_awards is Array:
		for raw_award: Variant in raw_awards:
			if raw_award is Dictionary:
				result[int(raw_award.get("seat_index", -1))] = raw_award
	return result


func _claim_outcome_text(
	claim: Dictionary,
	card_by_id: Dictionary,
	awards_by_seat: Dictionary
) -> String:
	var seat_index := int(claim.get("seat_index", -1))
	var participant_name := _participant_name(seat_index)
	var card_id: Variant = claim.get("card_id", null)
	if card_id == null:
		return "%s · 不抢 +1 分" % participant_name
	var claimed_card: Variant = card_by_id.get(str(card_id), {})
	var claimed_text := _format_card(claimed_card)
	var award: Dictionary = awards_by_seat.get(seat_index, {})
	if award.is_empty():
		return "%s · 抢 %s · 未获得" % [participant_name, claimed_text]
	var awarded_text := _format_card(award.get("card", {}))
	if str(award.get("source", "")) == "unique":
		return "%s · 抢 %s · 独得 %s" % [participant_name, claimed_text, awarded_text]
	return "%s · 抢 %s · 撞车得 %s" % [participant_name, claimed_text, awarded_text]


func _discarded_cards_text(raw_cards: Variant) -> String:
	if not raw_cards is Array:
		return ""
	var values: Array[String] = []
	for raw_card: Variant in raw_cards:
		if raw_card is Dictionary:
			values.append(_format_card(raw_card))
	return "、".join(values)


func _refresh_hand() -> void:
	var previous_selected_card_ids := _selected_card_ids.duplicate()
	var preserve_selection := _can_preserve_hand_selection()
	_clear_hand()
	var hand: Array[Dictionary] = CardRules.sort_cards(_store.get_local_hand())
	var acquired_card_ids: Array[String] = []
	if _store.has_method("get_acquired_card_ids"):
		acquired_card_ids = _store.get_acquired_card_ids()
	var acquired_card_source := ""
	if _store.has_method("get_acquired_card_source"):
		acquired_card_source = str(_store.get_acquired_card_source())
	_hand_title_label.text = "我的手牌（%d）" % hand.size()
	for index in range(hand.size()):
		var card_id := str(hand[index].get("id", ""))
		var is_acquired := acquired_card_ids.has(card_id)
		if (
			preserve_selection
			and previous_selected_card_ids.has(card_id)
			and _can_select_hand_card(card_id)
		):
			_selected_card_ids.append(card_id)
		var final_group_index := _final_group_index_for_card(card_id)
		var card := _build_hand_card(
			hand[index],
			index,
			is_acquired,
			acquired_card_source,
			final_group_index
		)
		card.disabled = not _can_select_hand_card(card_id)
		card.set_pressed_no_signal(
			final_group_index >= 0 or _selected_card_ids.has(card_id)
		)
		_hand_row.add_child(card)
		_hand_cards.append(card)
	if hand.is_empty():
		var empty := _label("等待私有手牌", 12, COLOR_MUTED)
		empty.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		_hand_row.add_child(empty)
	_update_play_selection_controls()
	_discard_button.disabled = not _can_discard_hand() or _selected_card_ids.size() != 1
	call_deferred("_on_resized")


func _can_preserve_hand_selection() -> bool:
	if _store == null:
		return false
	var phase := str(_store.phase)
	return (
		phase in ["actor_play", "award_discard"]
		and phase == _last_phase
		and int(_store.get("action_id")) == _last_action_id
	)


func _clear_hand() -> void:
	for child in _hand_row.get_children():
		child.free()
	_hand_cards.clear()
	_selected_card_ids.clear()
	_hand_title_label.text = "我的手牌（0）"
	if _play_button != null:
		_play_button.disabled = true
	if _hint_button != null:
		_hint_button.disabled = true
	if _play_preview_label != null:
		_play_preview_label.visible = false
		_play_preview_label.text = ""
	if _discard_button != null:
		_discard_button.disabled = true


func _build_hand_card(
	card: Dictionary,
	index: int,
	is_acquired: bool,
	acquired_card_source: String,
	final_group_index: int
) -> Button:
	var panel := Button.new()
	panel.name = "HandCard%d" % index
	panel.custom_minimum_size = Vector2(CARD_WIDTH, CARD_HEIGHT)
	panel.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	panel.toggle_mode = true
	panel.focus_mode = Control.FOCUS_ALL
	panel.set_meta("card_id", str(card.get("id", "")))
	panel.add_theme_stylebox_override(
		"normal",
		_style_box(
			COLOR_SURFACE_RAISED,
			COLOR_ACQUIRED if is_acquired else COLOR_BORDER,
			2 if is_acquired else 1,
			4
		)
	)
	panel.add_theme_stylebox_override(
		"hover",
		_style_box(
			Color("#293032"),
			COLOR_ACQUIRED if is_acquired else COLOR_GREEN,
			2 if is_acquired else 1,
			4
		)
	)
	panel.add_theme_stylebox_override("pressed", _style_box(Color("#30362f"), COLOR_GOLD, 3, 4))
	panel.add_theme_stylebox_override(
		"disabled",
		_style_box(
			COLOR_SURFACE,
			COLOR_ACQUIRED if is_acquired else COLOR_BORDER,
			2 if is_acquired else 1,
			4
		)
	)
	var tooltip_parts: Array[String] = [_format_card(card)]
	if is_acquired:
		tooltip_parts.append(_acquisition_text(acquired_card_source))
	if final_group_index >= 0:
		tooltip_parts.append("%s 组" % ("A" if final_group_index == 0 else "B"))
	panel.tooltip_text = " · ".join(tooltip_parts)
	panel.toggled.connect(_on_hand_card_toggled.bind(str(card.get("id", "")), panel))
	panel.clip_contents = true
	var face := _build_card_face(card, Vector2.ZERO)
	face.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	face.offset_left = 2
	face.offset_top = 2
	face.offset_right = -2
	face.offset_bottom = -2
	panel.add_child(face)
	var accessible_name := _label(_format_card(card), 1, Color.TRANSPARENT)
	accessible_name.name = "AccessibleCardName"
	accessible_name.visible = false
	panel.add_child(accessible_name)
	var marker_parts: Array[String] = []
	if _store != null and str(_store.deck_mode) == "two":
		marker_parts.append("#%d" % (int(card.get("copy_index", 0)) + 1))
	if is_acquired:
		marker_parts.append(_acquisition_text(acquired_card_source))
	elif final_group_index >= 0:
		marker_parts.append("%s组" % ("A" if final_group_index == 0 else "B"))
	if not marker_parts.is_empty():
		var marker_color := COLOR_ACQUIRED if is_acquired else (COLOR_GOLD if final_group_index >= 0 else COLOR_MUTED)
		var marker := _label(" · ".join(marker_parts), 8, marker_color)
		marker.name = "CardMarker"
		marker.mouse_filter = Control.MOUSE_FILTER_IGNORE
		marker.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		marker.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		marker.clip_text = true
		marker.add_theme_stylebox_override(
			"normal",
			_style_box(Color(0.05, 0.06, 0.07, 0.9), Color.TRANSPARENT, 0, 0)
		)
		marker.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
		marker.offset_left = 2
		marker.offset_top = -16
		marker.offset_right = -2
		marker.offset_bottom = -2
		panel.add_child(marker)
	return panel


func _build_card_face(card: Dictionary, minimum_size: Vector2) -> TextureRect:
	var face := TextureRect.new()
	face.name = "CardFace"
	face.custom_minimum_size = minimum_size
	face.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	face.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	face.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	face.mouse_filter = Control.MOUSE_FILTER_IGNORE
	face.texture = CardFaceCatalog.texture_for(card)
	face.tooltip_text = _format_card(card)
	return face


func _acquisition_text(source: String) -> String:
	return "出牌获得" if source == "play" else "抢牌获得"


func _can_select_hand() -> bool:
	return (
		_store != null
		and _is_action_context_ready()
		and str(_store.phase) == "actor_play"
		and _local_seat_index >= 0
		and int(_store.actor_seat_index) == _local_seat_index
	)


func _is_action_context_ready() -> bool:
	return (
		_store != null
		and _store.has_method("is_action_context_ready")
		and bool(_store.is_action_context_ready())
	)


func _refresh_connection_label() -> void:
	if _connection_label == null:
		return
	if _store == null:
		_connection_label.text = "等待状态"
		return
	var state := str(_store.get("connection_state"))
	if state == "reconnecting":
		_connection_label.text = "重连中"
		return
	if state != "connected" or not _is_action_context_ready():
		_connection_label.text = "同步中"
		return
	var deadline_at_unix_ms := float(_store.get("action_deadline_at_unix_ms"))
	if deadline_at_unix_ms <= 0.0:
		_connection_label.text = "等待"
		return
	var remaining_ms := deadline_at_unix_ms - float(_time_source.call())
	if remaining_ms <= 0.0:
		_connection_label.text = "等待服务器"
		return
	_connection_label.text = "剩余 %d 秒" % ceili(remaining_ms / 1000.0)


func _can_select_hand_card(card_id: String) -> bool:
	if _can_select_hand():
		return true
	if _can_edit_final_groups():
		return not card_id.is_empty()
	return (
		_can_discard_hand()
		and not card_id.is_empty()
	)


func _can_discard_hand() -> bool:
	return (
		_show_discard_controls()
		and _is_action_context_ready()
		and not _discard_submission_pending
	)


func _show_discard_controls() -> bool:
	return (
		_store != null
		and str(_store.phase) == "award_discard"
		and _is_local_discard_pending()
	)


func _show_final_controls() -> bool:
	return false


func _can_edit_final_groups() -> bool:
	return (
		_show_final_controls()
		and _is_action_context_ready()
		and not _final_submission_pending
	)


func _final_group_index_for_card(card_id: String) -> int:
	for group_index in range(_final_group_ids.size()):
		var raw_group: Variant = _final_group_ids[group_index]
		if raw_group is Array and raw_group.has(card_id):
			return group_index
	return -1


func _is_local_discard_pending() -> bool:
	if (
		_store == null
		or _local_seat_index < 0
		or not _store.has_method("get_pending_discard_seat_indexes")
	):
		return false
	var pending_seat_indexes: Array[int] = _store.get_pending_discard_seat_indexes()
	return pending_seat_indexes.has(_local_seat_index)


func _can_choose_claim() -> bool:
	return (
		_show_claim_controls()
		and _is_action_context_ready()
		and not _claim_submission_pending
		and not bool(_store.claim_committed)
	)


func _show_claim_controls() -> bool:
	return (
		_store != null
		and str(_store.phase) == "claim_commit"
		and _local_seat_index >= 0
		and int(_store.actor_seat_index) != _local_seat_index
	)


func _on_claim_card_toggled(pressed: bool, card_id: String, button: Button) -> void:
	if not _can_choose_claim() or card_id.is_empty():
		button.set_pressed_no_signal(false)
		return
	if pressed:
		_selected_claim_card_id = card_id
	elif _selected_claim_card_id == card_id:
		_selected_claim_card_id = ""
	_submit_claim_button.disabled = _selected_claim_card_id.is_empty()


func _on_submit_claim_pressed() -> void:
	if not _can_choose_claim() or _selected_claim_card_id.is_empty():
		return
	_begin_claim_submission(_selected_claim_card_id)


func _on_pass_claim_pressed() -> void:
	if not _can_choose_claim():
		return
	_begin_claim_submission(null)


func _begin_claim_submission(card_id: Variant) -> void:
	_claim_submission_pending = true
	_action_error_label.text = ""
	_action_error_label.tooltip_text = ""
	for child in _played_cards_row.get_children():
		if child is Button:
			(child as Button).disabled = true
	_submit_claim_button.disabled = true
	_pass_claim_button.disabled = true
	_action_prompt_label.text = "抢牌选择提交中：等待服务器确认"
	_store.claim_card(card_id)


func _on_hand_card_toggled(pressed: bool, card_id: String, button: Button) -> void:
	if _store != null and str(_store.phase) == "final_commit":
		_on_final_hand_card_toggled(card_id, button)
		return
	if not _can_select_hand_card(card_id):
		button.set_pressed_no_signal(false)
		return
	if pressed:
		if _can_discard_hand():
			for hand_card in _hand_cards:
				if hand_card != button:
					hand_card.set_pressed_no_signal(false)
			_selected_card_ids.clear()
		elif _selected_card_ids.size() >= 3:
			button.set_pressed_no_signal(false)
			return
		if not _selected_card_ids.has(card_id):
			_selected_card_ids.append(card_id)
	else:
		_selected_card_ids.erase(card_id)
	_update_play_selection_controls()
	_discard_button.disabled = not _can_discard_hand() or _selected_card_ids.size() != 1


func _on_final_hand_card_toggled(card_id: String, button: Button) -> void:
	if not _can_edit_final_groups() or card_id.is_empty():
		button.set_pressed_no_signal(_final_group_index_for_card(card_id) >= 0)
		return
	var current_group_index := _final_group_index_for_card(card_id)
	var active_group: Array = _final_group_ids[_active_final_group]
	if current_group_index == _active_final_group:
		active_group.erase(card_id)
	elif active_group.size() < 3:
		if current_group_index >= 0:
			var previous_group: Array = _final_group_ids[current_group_index]
			previous_group.erase(card_id)
		active_group.append(card_id)
	call_deferred("_refresh")


func _on_final_group_mode_toggled(pressed: bool, group_index: int) -> void:
	if not pressed:
		return
	_active_final_group = group_index


func _on_lock_final_pressed() -> void:
	if not _can_edit_final_groups() or not _is_valid_final_groups(_final_group_ids):
		return
	_begin_final_submission(false)


func _on_best_final_pressed() -> void:
	if not _can_edit_final_groups():
		return
	_begin_final_submission(true)


func _begin_final_submission(use_best: bool) -> void:
	_final_submission_pending = true
	_action_error_label.text = ""
	_action_error_label.tooltip_text = ""
	for hand_card in _hand_cards:
		hand_card.disabled = true
	for button in [
		_final_group_a_button,
		_final_group_b_button,
		_lock_final_button,
		_best_final_button,
	]:
		button.disabled = true
	_action_prompt_label.text = "最终选择提交中：等待服务器确认"
	if use_best:
		_store.submit_best_final_selection()
	else:
		_store.submit_final_selection(_final_group_ids.duplicate(true))


func _on_play_pressed() -> void:
	if not _can_select_hand() or _selected_card_ids.size() != 3:
		return
	_action_error_label.text = ""
	_action_error_label.tooltip_text = ""
	_store.play_cards(_selected_card_ids.duplicate())


func _on_hint_pressed() -> void:
	if not _can_select_hand():
		return
	var best := CardRules.find_best_three(_store.get_local_hand())
	if best.is_empty():
		return
	_selected_card_ids.clear()
	var raw_card_ids: Variant = best.get("card_ids", [])
	if raw_card_ids is Array:
		for raw_card_id: Variant in raw_card_ids:
			_selected_card_ids.append(str(raw_card_id))
	for hand_card in _hand_cards:
		hand_card.set_pressed_no_signal(
			_selected_card_ids.has(str(hand_card.get_meta("card_id", "")))
		)
	_update_play_selection_controls()


func _update_play_selection_controls() -> void:
	_play_button.disabled = not _can_select_hand() or _selected_card_ids.size() != 3
	_refresh_play_preview()


func _refresh_play_preview() -> void:
	_play_preview_label.visible = false
	_play_preview_label.text = ""
	if _play_button.disabled or _selected_card_ids.size() != 3 or _store == null:
		return
	var selected_cards: Array = []
	for card: Dictionary in _store.get_local_hand():
		if _selected_card_ids.has(str(card.get("id", ""))):
			selected_cards.append(card)
	var evaluation := CardRules.evaluate_three(selected_cards)
	if evaluation.is_empty():
		return
	_play_preview_label.text = "%s · +%d 分" % [
		str(evaluation.get("label", "")),
		int(evaluation.get("score", 0)),
	]
	_play_preview_label.visible = true


func _on_return_to_lobby_pressed() -> void:
	if _store == null or str(_store.phase) != "finished" or _return_to_lobby_pending:
		return
	_return_to_lobby_pending = true
	_return_to_lobby_button.disabled = true
	_action_prompt_label.text = "正在返回大厅"
	return_to_lobby_requested.emit()


func _on_discard_pressed() -> void:
	if not _can_discard_hand() or _selected_card_ids.size() != 1:
		return
	_discard_submission_pending = true
	_action_error_label.text = ""
	_action_error_label.tooltip_text = ""
	for hand_card in _hand_cards:
		hand_card.disabled = true
	_discard_button.disabled = true
	_action_prompt_label.text = "弃牌提交中：等待服务器确认"
	_store.discard_card(_selected_card_ids[0], int(_store.turn_number))


func _refresh_action_prompt(phase: String, actor_seat_index: int, local_seat_index: int) -> void:
	var show_claim_controls := _show_claim_controls()
	var can_choose_claim := _can_choose_claim()
	var show_discard_controls := _show_discard_controls()
	var show_final_controls := _show_final_controls()
	_play_button.visible = phase in ["actor_play", "claim_commit"]
	_hint_button.visible = phase == "actor_play"
	_hint_button.disabled = not _can_select_hand()
	_return_to_lobby_button.visible = phase == "finished"
	if phase != "finished":
		_return_to_lobby_pending = false
	_return_to_lobby_button.disabled = _return_to_lobby_pending
	_discard_button.visible = show_discard_controls
	_discard_button.disabled = not _can_discard_hand() or _selected_card_ids.size() != 1
	_submit_claim_button.visible = show_claim_controls
	_submit_claim_button.disabled = not can_choose_claim or _selected_claim_card_id.is_empty()
	_pass_claim_button.visible = show_claim_controls
	_pass_claim_button.disabled = not _can_choose_claim()
	_set_final_controls_visible(show_final_controls)
	_final_group_a_button.disabled = not _can_edit_final_groups()
	_final_group_b_button.disabled = not _can_edit_final_groups()
	_final_group_a_button.set_pressed_no_signal(_active_final_group == 0)
	_final_group_b_button.set_pressed_no_signal(_active_final_group == 1)
	_lock_final_button.disabled = (
		not _can_edit_final_groups()
		or not _is_valid_final_groups(_final_group_ids)
	)
	_best_final_button.disabled = not _can_edit_final_groups()
	if phase in ["actor_play", "claim_commit", "award_discard", "final_commit"] and not _is_action_context_ready():
		_action_prompt_label.text = (
			"重连中：等待权威状态"
			if str(_store.get("connection_state")) == "reconnecting"
			else "同步中：等待权威状态"
		)
	elif phase == "point_contest":
		_action_prompt_label.text = "拼点进行中：所有公开翻牌后决定首位行动者"
	elif phase == "actor_play":
		if actor_seat_index == local_seat_index:
			_action_prompt_label.text = "轮到你：从手牌选择三张牌出牌"
		else:
			_action_prompt_label.text = "等待 %s 出牌" % _participant_name(actor_seat_index)
	elif phase == "play_reveal":
		_action_prompt_label.text = "出牌公示中：查看行动者出的牌、牌型与加点"
	elif phase == "claim_commit":
		if actor_seat_index == local_seat_index:
			_action_prompt_label.text = "本轮由你出牌：等待其他参与者抢牌"
		elif _claim_submission_pending:
			_action_prompt_label.text = "抢牌选择提交中：等待服务器确认"
		elif bool(_store.claim_committed):
			_action_prompt_label.text = "抢牌选择已提交：等待其他参与者"
		else:
			_action_prompt_label.text = "选择一张牌抢牌，或选择不抢"
	elif phase == "claim_reveal":
		_action_prompt_label.text = "抢牌选择同时揭晓中"
	elif phase == "award_discard":
		var local_award := _current_local_award()
		if _discard_submission_pending and show_discard_controls:
			_action_prompt_label.text = "弃牌提交中：等待服务器确认"
		elif show_discard_controls:
			_action_prompt_label.text = "你获得了 %s：请选择任意一张手牌弃置" % _format_card(local_award)
		elif not local_award.is_empty():
			_action_prompt_label.text = "弃牌已完成：等待其他参与者"
		else:
			_action_prompt_label.text = "等待获得牌的参与者弃牌"
	elif phase == "discard_reveal":
		_action_prompt_label.text = "弃牌公示中：即将进入下一回合"
	elif phase == "final_commit":
		_action_prompt_label.text = "最终结算：服务器正在选择最佳三张"
	elif phase == "final_reveal":
		_action_prompt_label.text = "最终组合已统一揭晓：核对结算得分"
	elif phase == "finished":
		_action_prompt_label.text = "对局结束：查看最终排名"
	else:
		_action_prompt_label.text = "等待服务器状态"
	_refresh_play_preview()


func _current_local_award() -> Dictionary:
	if _store == null or _local_seat_index < 0:
		return {}
	var claim_event := _current_claim_event()
	var raw_awards: Variant = claim_event.get("awards", [])
	if not raw_awards is Array:
		return {}
	for raw_award: Variant in raw_awards:
		if (
			raw_award is Dictionary
			and int(raw_award.get("seat_index", -1)) == _local_seat_index
		):
			var card: Variant = raw_award.get("card", {})
			return card if card is Dictionary else {}
	return {}


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
	var compact_final_settlement := (
		_store != null
		and str(_store.phase) in ["final_reveal", "finished"]
		and (width < 900.0 or stage_height < 400.0)
	)
	for seat_panel in _seat_cards:
		seat_panel.visible = not compact_final_settlement
	if compact_final_settlement:
		for action_panel in _seat_action_panels:
			action_panel.visible = false
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
	var current_phase := str(_store.phase) if _store != null else ""
	var show_compact_discard_status := current_phase in ["award_discard", "discard_reveal"]
	var seat_positions := {
		local_index: Vector2(north_x, local_y),
		posmod(local_index + 1, 4): Vector2(east_x, side_y),
		posmod(local_index + 2, 4): Vector2(north_x, north_y),
		posmod(local_index + 3, 4): Vector2(8.0, side_y),
	}
	for seat_index in range(4):
		_seat_cards[seat_index].position = seat_positions.get(seat_index, Vector2.ZERO)
		_seat_cards[seat_index].size = Vector2(seat_width, seat_height)
		var seat_position: Vector2 = seat_positions.get(seat_index, Vector2.ZERO)
		var action_panel := _seat_action_panels[seat_index]
		var action_size := action_panel.custom_minimum_size
		var relative_position := posmod(seat_index - local_index, 4)
		var action_position := Vector2.ZERO
		match relative_position:
			0:
				action_position = Vector2(
					seat_position.x + (seat_width - action_size.x) * 0.5,
					seat_position.y - action_size.y - 5.0
				)
			1:
				action_position = Vector2(
					seat_position.x - action_size.x - 5.0,
					seat_position.y + (seat_height - action_size.y) * 0.5
				)
			2:
				action_position = Vector2(
					seat_position.x + (seat_width - action_size.x) * 0.5,
					seat_position.y + seat_height + 5.0
				)
			3:
				action_position = Vector2(
					seat_position.x + seat_width + 5.0,
					seat_position.y + (seat_height - action_size.y) * 0.5
				)
		if show_compact_discard_status and relative_position == 2:
			action_position.x = (
				width * 0.5 - DISCARD_STATUS_WIDTH * 0.5 - action_size.x - 6.0
			)
		elif show_compact_discard_status and relative_position == 0:
			action_position.x = width * 0.5 + DISCARD_STATUS_WIDTH * 0.5 + 6.0
		action_position.x = clampf(action_position.x, 4.0, maxf(4.0, width - action_size.x - 4.0))
		action_position.y = clampf(action_position.y, 4.0, maxf(4.0, stage_height - action_size.y - 4.0))
		action_panel.position = action_position
		action_panel.size = action_size

	# Four public reveals must fit in the center at the minimum supported width.
	var contest_width := (
		DISCARD_STATUS_WIDTH
		if show_compact_discard_status
		else minf(280.0, maxf(220.0, width * 0.42))
	)
	var contest_height := (
		DISCARD_STATUS_HEIGHT
		if show_compact_discard_status
		else maxf(76.0, _contest_panel.get_combined_minimum_size().y)
	)
	var contest_y := (
		(stage_height - contest_height) * 0.5
		if show_compact_discard_status
		else maxf(78.0, (stage_height - contest_height) * 0.46)
	)
	_contest_panel.position = Vector2((width - contest_width) * 0.5, contest_y)
	_contest_panel.size = Vector2(contest_width, contest_height)
	var show_final_settlement := (
		_store != null
		and str(_store.phase) in ["final_reveal", "finished"]
		and _played_panel.visible
	)
	var played_width := (
		minf(560.0, maxf(340.0, width - 32.0))
		if show_final_settlement
		else minf(340.0, maxf(280.0, width * 0.5))
	)
	var played_height := maxf(108.0, _played_panel.get_combined_minimum_size().y)
	var played_y := maxf(78.0, (stage_height - played_height) * 0.46)
	if show_final_settlement and compact_final_settlement:
		played_y = clampf(
			(stage_height - played_height) * 0.5,
			8.0,
			maxf(8.0, stage_height - played_height - 8.0)
		)
	_played_panel.position = Vector2((width - played_width) * 0.5, played_y)
	_played_panel.size = Vector2(played_width, played_height)


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


func _settlement_participant_name(seat_index: int) -> String:
	var nickname := _participant_name(seat_index)
	var participant: Dictionary = _participant_by_seat.get(seat_index, {})
	if bool(participant.get("is_bot", false)) and not nickname.contains("机器人"):
		return "%s（机器人）" % nickname
	return nickname


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
	var copy_marker := ""
	if _store != null and str(_store.deck_mode) == "two":
		copy_marker = " #%d" % (int(card.get("copy_index", 0)) + 1)
	return "%s %s%s" % [
		_rank_text(int(card.get("rank", 0))),
		_suit_text(card.get("suit", "")),
		copy_marker,
	]


func _compact_card(card: Dictionary) -> String:
	var suit_symbol := "?"
	match str(card.get("suit", "")):
		"clubs":
			suit_symbol = "♣"
		"spades":
			suit_symbol = "♠"
		"diamonds":
			suit_symbol = "♦"
		"hearts":
			suit_symbol = "♥"
	var copy_marker := ""
	if _store != null and str(_store.deck_mode) == "two":
		copy_marker = "#%d" % (int(card.get("copy_index", 0)) + 1)
	return "%s%s%s" % [_rank_text(int(card.get("rank", 0))), suit_symbol, copy_marker]


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
		"play_reveal":
			return "出牌公示"
		"claim_commit":
			return "抢牌"
		"claim_reveal":
			return "抢牌揭晓"
		"award_discard":
			return "弃牌"
		"discard_reveal":
			return "弃牌公示"
		"final_commit":
			return "最终结算"
		"final_reveal":
			return "结算揭晓"
		"finished":
			return "已结束"
	return "同步中"


func _combination_text(category: String) -> String:
	return CombinationCatalog.label(category)


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
