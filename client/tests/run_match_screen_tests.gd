extends SceneTree

const MatchScreen = preload("res://scripts/match/match_screen.gd")

var _failures: Array[String] = []


class FakeMatchStore extends RefCounted:
	signal state_changed()
	signal private_state_changed()
	signal action_failed(code: String, message: String)

	var phase := "actor_play"
	var actor_seat_index := 2
	var draw_pile_count := 20
	var room_id := "room-a"
	var local_participant_id := "human-a"
	var turn_number := 0
	var played_category := ""
	var played_score := 0
	var claim_commit_count := 0
	var claim_committed := false
	var claim_card_id: Variant = null
	var _participants: Array[Dictionary] = []
	var _contest_rounds: Array[Dictionary] = []
	var _played_cards: Array[Dictionary] = []
	var _play_events: Array[Dictionary] = []
	var _claim_events: Array[Dictionary] = []
	var _revealed_claims: Array[Dictionary] = []
	var _claim_awards: Array[Dictionary] = []
	var _discarded_cards: Array[Dictionary] = []
	var _local_hand: Array[Dictionary] = []
	var play_requests: Array[Array] = []
	var claim_requests: Array[Variant] = []

	func get_participants() -> Array[Dictionary]:
		return _participants

	func get_contest_rounds() -> Array[Dictionary]:
		return _contest_rounds

	func get_local_hand() -> Array[Dictionary]:
		return _local_hand

	func get_played_cards() -> Array[Dictionary]:
		return _played_cards

	func get_play_events() -> Array[Dictionary]:
		return _play_events

	func get_claim_events() -> Array[Dictionary]:
		return _claim_events

	func get_revealed_claims() -> Array[Dictionary]:
		return _revealed_claims

	func get_claim_awards() -> Array[Dictionary]:
		return _claim_awards

	func get_discarded_cards() -> Array[Dictionary]:
		return _discarded_cards

	func play_cards(card_ids: Array[String]) -> void:
		play_requests.append(card_ids.duplicate())

	func claim_card(card_id: Variant) -> void:
		claim_requests.append(card_id)

	func publish() -> void:
		state_changed.emit()


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var store := FakeMatchStore.new()
	store._participants = [
		_seat(0, "human-a", "甲", false, 0, 8),
		_seat(1, "human-b", "乙", false, 2, 8),
		_seat(2, "bot-c", "机器人丙", true, 4, 8),
		_seat(3, "bot-d", "机器人丁", true, 1, 8),
	]
	store._participants[1]["hand"] = [_card("secret-opponent-card", 14, "spades", 0)]
	store._participants[1]["private_claim"] = "secret-opponent-claim"
	store._contest_rounds = [
		{
			"round_index": 0,
			"reveals": [
				{"seat_index": 0, "card": _card("copy-0:hearts:14", 14, "hearts", 0)},
				{"seat_index": 1, "card": _card("copy-0:hearts:13", 13, "hearts", 0)},
			],
			"tied_seat_indexes": [0, 1],
			"winner_seat_index": -1,
		},
		{
			"round_index": 1,
			"reveals": [
				{"seat_index": 0, "card": _card("copy-0:spades:10", 10, "spades", 0)},
				{"seat_index": 1, "card": _card("copy-0:hearts:9", 9, "hearts", 0)},
				{"seat_index": 2, "card": _card("copy-0:diamonds:8", 8, "diamonds", 0)},
				{"seat_index": 3, "card": _card("copy-0:clubs:7", 7, "clubs", 0)},
			],
			"tied_seat_indexes": [],
			"winner_seat_index": 0,
		},
	]
	var screen := MatchScreen.new()
	screen.name = "MatchScreenTestSubject"
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(960, 540)
	screen.set_match_store(store)
	root.add_child(screen)
	await process_frame
	await process_frame

	_test_four_seats_are_visible(screen, Vector2(960, 540), 2)
	_test_public_header_and_contest_history_are_visible(screen)
	_expect_equal(screen._hand_cards.size(), 0, "拼点展示期间尚未收到私有手牌")
	for rank in [2, 5, 8, 11, 12, 13, 14, 10]:
		store._local_hand.append(_card("local-%s" % rank, rank, "hearts" if rank >= 11 else "clubs", 0))
	store.private_state_changed.emit()
	await process_frame
	await process_frame
	_test_local_hand_is_readable_and_private(screen)
	await _test_only_local_actor_can_select_exactly_three_and_play(screen, store)
	await _test_claim_commit_shows_played_combination(screen, store)
	await _test_actor_only_sees_claim_waiting_state(screen, store)
	await _test_non_actor_can_choose_one_claim_or_pass(screen, store)
	await _test_selected_claim_submits_physical_id_and_stays_pending(screen, store)
	await _test_private_claim_confirmation_shows_waiting_state(screen, store)
	await _test_pass_submits_null_and_enters_pending(screen, store)
	await _test_claim_reveal_shows_simultaneous_outcomes_and_public_history(screen, store)
	await _test_collision_outcome_moves_once_without_resizing(screen, store)
	await _test_new_room_replays_collision_motion(screen, store)
	await _test_public_history_is_chronological(screen, store)
	await _test_rejected_claim_reenables_controls_without_moving_layout(screen, store)
	await _test_action_error_is_visible_without_moving_controls(screen, store)
	await _test_unbinding_store_clears_pending_claim_controls(screen, store)
	_test_key_regions_do_not_overlap(screen, Vector2(960, 540))
	screen.size = Vector2(1280, 720)
	await process_frame
	await process_frame
	_test_four_seats_are_visible(screen, Vector2(1280, 720), 0)
	_test_key_regions_do_not_overlap(screen, Vector2(1280, 720))
	screen.set_match_store(null)
	await process_frame
	_expect_equal(screen._hand_cards.size(), 0, "解除状态源后不残留私有手牌")
	_expect(not _node_text(screen).contains("机器人丙"), "解除状态源后不残留参与者信息")

	screen.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: match screen layout tests")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_four_seats_are_visible(
	screen: MatchScreen,
	viewport_size: Vector2,
	actor_seat_index: int
) -> void:
	_expect_equal(screen._seat_cards.size(), 4, "固定四席")
	for index in range(4):
		var rect := screen._seat_cards[index].get_global_rect()
		_expect(rect.size.x >= 140.0 and rect.size.y >= 50.0, "席位 %d 尺寸稳定" % index)
		_expect(rect.position.x >= 0.0 and rect.position.y >= 0.0, "席位 %d 不越出左上边界" % index)
		_expect(rect.end.x <= viewport_size.x and rect.end.y <= viewport_size.y, "席位 %d 不越出视口" % index)
	_expect(screen._seat_name_labels[0].text == "甲", "本地参与者昵称可见")
	_expect(screen._seat_name_labels[2].text == "机器人丙", "机器人昵称可见")
	_expect(screen._seat_role_labels[actor_seat_index].text.contains("行动中"), "行动者高亮")


func _test_public_header_and_contest_history_are_visible(screen: MatchScreen) -> void:
	_expect(screen._phase_label.text.contains("出牌"), "阶段显示出牌")
	_expect(screen._actor_label.text.contains("机器人丙"), "行动者显示昵称")
	_expect(screen._deck_label.text.contains("20"), "牌堆数量显示")
	_expect(screen._history_list.get_child_count() == 2, "拼点历史显示两轮")
	_expect(screen._contest_title_label.text.contains("第 2 轮"), "中央显示最新拼点轮次")
	_expect(screen._contest_reveal_row.get_child_count() == 4, "中央显示最新公开翻牌")
	for reveal in screen._contest_reveal_row.get_children():
		_expect(reveal.get_global_rect().end.x <= screen._contest_panel.get_global_rect().end.x, "中央公开翻牌不被裁出")


func _test_local_hand_is_readable_and_private(screen: MatchScreen) -> void:
	_expect_equal(screen._hand_cards.size(), 8, "本地手牌八张")
	for card in screen._hand_cards:
		var rect := card.get_global_rect()
		_expect(rect.size.x >= 45.0 and rect.size.y >= 60.0, "本地牌保持可读尺寸")
		_expect(rect.end.x <= 960.0 and rect.end.y <= 540.0, "本地牌不越出视口")
		var card_text := _node_text(card)
		_expect(not card_text.is_empty(), "本地牌显示牌面")
		_expect(card_text.contains("♣") or card_text.contains("♥"), "本地牌同时显示花色符号")
	_expect(screen._hand_title_label.text.contains("8"), "本地手牌数量显示")
	_expect(not _node_text(screen).contains("secret-opponent-card"), "不显示对手私有牌面")


func _test_only_local_actor_can_select_exactly_three_and_play(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	var play_button := screen.find_child("PlayCardsButton", true, false) as Button
	if play_button == null:
		_failures.append("比赛界面应提供稳定的出牌按钮")
		return
	_expect(play_button.disabled, "非本地行动者不能出牌")
	for index in range(screen._hand_cards.size()):
		var card_control: Variant = screen.find_child("HandCard%d" % index, true, false)
		_expect(card_control is Button and card_control.disabled, "非本地行动者不能选择手牌")

	store.actor_seat_index = 0
	store.publish()
	await process_frame
	await process_frame
	for index in range(screen._hand_cards.size()):
		var card_control: Variant = screen.find_child("HandCard%d" % index, true, false)
		_expect(card_control is Button and not card_control.disabled, "本地行动者可以选择手牌")
	for index in range(3):
		var card_button := screen.find_child("HandCard%d" % index, true, false) as Button
		card_button.button_pressed = true
	_expect(not play_button.disabled, "选满三张后启用出牌")
	_expect(_selected_card_count(screen) == 3, "三张手牌显示选中态")
	var fourth_card := screen.find_child("HandCard3", true, false) as Button
	fourth_card.button_pressed = true
	_expect(_selected_card_count(screen) == 3, "不能选择第四张手牌")
	_expect(not fourth_card.button_pressed, "被拒绝的第四张不显示选中")

	play_button.pressed.emit()
	_expect_equal(store.play_requests, [["local-2", "local-5", "local-8"]], "出牌按钮提交三张物理牌标识")
	store.actor_seat_index = 2
	store.publish()
	await process_frame
	await process_frame
	_expect(play_button.disabled, "行动权移交后禁用出牌")
	_expect(_selected_card_count(screen) == 0, "行动权移交后清空本地选择")


func _test_claim_commit_shows_played_combination(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	var played_panel := screen.find_child("PlayedCombinationPanel", true, false) as PanelContainer
	if played_panel == null:
		_failures.append("抢牌阶段应提供公开出牌区域")
		return
	store.phase = "claim_commit"
	store.actor_seat_index = 0
	store.turn_number = 1
	store._played_cards = [
		_card("played-queen", 12, "hearts", 0),
		_card("played-king", 13, "hearts", 0),
		_card("played-ace", 14, "hearts", 0),
	]
	store.played_category = "straight_flush"
	store.played_score = 10
	store._play_events = [{
		"turn_number": 1,
		"actor_seat_index": 0,
		"cards": store._played_cards.duplicate(true),
		"category": "straight_flush",
		"score": 10,
	}]
	store.publish()
	await process_frame
	await process_frame

	var played_row := screen.find_child("PlayedCardsRow", true, false) as HBoxContainer
	_expect(played_panel.visible, "抢牌阶段显示公开出牌区域")
	_expect(played_row != null and played_row.get_child_count() == 3, "公开展示三张已出牌")
	var played_text := _node_text(played_panel)
	_expect(played_text.contains("第 1 回合"), "公开出牌显示回合编号")
	_expect(played_text.contains("同花顺"), "公开出牌显示中文牌型")
	_expect(played_text.contains("10"), "公开出牌显示本次得分")
	var history_text := _node_text(screen._history_list)
	_expect(screen._history_list.get_child_count() == 3, "历史区在拼点后追加本轮出牌事件")
	_expect(history_text.contains("甲"), "出牌历史显示行动者")
	_expect(history_text.contains("同花顺"), "出牌历史显示中文牌型")
	_expect(history_text.contains("10"), "出牌历史显示本轮得分")
	_expect(_selected_card_count(screen) == 0, "抢牌阶段不保留出牌选择")
	var play_button := screen.find_child("PlayCardsButton", true, false) as Button
	_expect(play_button != null and play_button.disabled, "抢牌阶段禁用出牌按钮")
	for index in range(screen._hand_cards.size()):
		var card_control: Variant = screen.find_child("HandCard%d" % index, true, false)
		_expect(card_control is Button and card_control.disabled, "抢牌阶段本地手牌只读")


func _test_actor_only_sees_claim_waiting_state(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	store.claim_commit_count = 2
	store.publish()
	await process_frame
	await process_frame
	_expect(screen.find_child("ClaimCard0", true, false) == null, "行动者不显示抢牌选择控件")
	var submit_button := screen.find_child("SubmitClaimButton", true, false) as Button
	var pass_button := screen.find_child("PassClaimButton", true, false) as Button
	_expect(submit_button != null and not submit_button.visible, "行动者不显示抢牌按钮")
	_expect(pass_button != null and not pass_button.visible, "行动者不显示 Pass 按钮")
	_expect(screen._action_prompt_label.text.contains("2/3"), "行动者等待状态显示公开提交进度")
	store.claim_commit_count = 0
	store.publish()
	await process_frame
	await process_frame


func _test_non_actor_can_choose_one_claim_or_pass(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	store.actor_seat_index = 1
	store.publish()
	await process_frame
	await process_frame

	var pass_button := screen.find_child("PassClaimButton", true, false) as Button
	_expect(pass_button != null and pass_button.visible and not pass_button.disabled, "非行动者可以选择不抢")
	for index in range(3):
		var claim_card := screen.find_child("ClaimCard%d" % index, true, false) as Button
		_expect(claim_card != null and not claim_card.disabled, "非行动者可以选择公开牌 %d" % index)
	var first_card := screen.find_child("ClaimCard0", true, false) as Button
	var second_card := screen.find_child("ClaimCard1", true, false) as Button
	if first_card != null and second_card != null:
		first_card.button_pressed = true
		second_card.button_pressed = true
		_expect(not first_card.button_pressed, "选择另一张牌会取消原选择")
		_expect(second_card.button_pressed, "最后选择的牌保持选中")
	store.actor_seat_index = 0
	store.publish()
	await process_frame
	await process_frame


func _test_selected_claim_submits_physical_id_and_stays_pending(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	store.actor_seat_index = 1
	store.publish()
	await process_frame
	await process_frame
	var selected_card := screen.find_child("ClaimCard1", true, false) as Button
	var submit_button := screen.find_child("SubmitClaimButton", true, false) as Button
	if selected_card == null or submit_button == null:
		_failures.append("抢牌阶段应提供选牌提交控件")
	else:
		selected_card.button_pressed = true
		_expect(not submit_button.disabled, "选择一张公开牌后可以提交")
		submit_button.pressed.emit()
		_expect_equal(store.claim_requests, ["played-king"], "抢牌提交使用物理牌标识")
		_expect(submit_button.disabled and selected_card.disabled, "提交后立即禁用抢牌控件")
		_expect(screen._action_prompt_label.text.contains("提交中"), "私有确认前显示稳定提交状态")
		store.publish()
		await process_frame
		await process_frame
		var refreshed_submit := screen.find_child("SubmitClaimButton", true, false) as Button
		var refreshed_card := screen.find_child("ClaimCard1", true, false) as Button
		_expect(refreshed_submit != null and refreshed_submit.disabled, "公开刷新不重新启用提交")
		_expect(refreshed_card != null and refreshed_card.disabled, "公开刷新不重新启用选牌")
	store.actor_seat_index = 0
	store.publish()
	await process_frame
	await process_frame


func _test_private_claim_confirmation_shows_waiting_state(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	store.actor_seat_index = 1
	store.claim_commit_count = 1
	store.claim_committed = true
	store.claim_card_id = "played-king"
	store.private_state_changed.emit()
	await process_frame
	await process_frame

	var submit_button := screen.find_child("SubmitClaimButton", true, false) as Button
	var selected_card := screen.find_child("ClaimCard1", true, false) as Button
	_expect(submit_button != null and submit_button.disabled, "私有确认后提交控件保持禁用")
	_expect(selected_card != null and selected_card.disabled, "私有确认后公开牌保持只读")
	_expect(screen._action_prompt_label.text.contains("已提交"), "私有确认后显示已提交")
	_expect(screen._action_prompt_label.text.contains("1/3"), "等待状态显示公开提交进度")
	store.actor_seat_index = 0
	store.publish()
	await process_frame
	await process_frame


func _test_pass_submits_null_and_enters_pending(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	store.phase = "actor_play"
	store.actor_seat_index = 0
	store.claim_commit_count = 0
	store.claim_committed = false
	store.claim_card_id = null
	store.publish()
	store.private_state_changed.emit()
	await process_frame
	await process_frame
	store.phase = "claim_commit"
	store.actor_seat_index = 1
	store.publish()
	await process_frame
	await process_frame

	var pass_button := screen.find_child("PassClaimButton", true, false) as Button
	if pass_button == null:
		_failures.append("抢牌阶段应提供不抢按钮")
	else:
		pass_button.pressed.emit()
		_expect_equal(store.claim_requests, ["played-king", null], "不抢提交空牌标识")
		_expect(pass_button.disabled, "不抢提交后立即禁用抢牌控件")
		_expect(screen._action_prompt_label.text.contains("提交中"), "不抢后显示稳定提交状态")
	store.actor_seat_index = 0
	store.publish()
	await process_frame
	await process_frame


func _test_claim_reveal_shows_simultaneous_outcomes_and_public_history(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	var queen := _card("played-queen", 12, "hearts", 0)
	var king := _card("played-king", 13, "hearts", 0)
	var ace := _card("played-ace", 14, "hearts", 0)
	store.phase = "claim_reveal"
	store.turn_number = 2
	store.actor_seat_index = 0
	store._played_cards = []
	store._revealed_claims = [
		{"seat_index": 1, "card_id": "played-ace"},
		{"seat_index": 2, "card_id": "played-queen"},
		{"seat_index": 3, "card_id": "played-queen"},
	]
	store._claim_awards = [
		{"seat_index": 1, "card": ace, "source": "unique"},
		{"seat_index": 2, "card": king, "source": "collision"},
		{"seat_index": 3, "card": queen, "source": "collision"},
	]
	store._discarded_cards = []
	store._claim_events = [
		{
			"turn_number": 1,
			"claims": [
				{"seat_index": 1, "card_id": null},
				{"seat_index": 2, "card_id": null},
				{"seat_index": 3, "card_id": null},
			],
			"awards": [],
			"discarded_cards": [queen, king, ace],
		},
		{
			"turn_number": 2,
			"claims": store._revealed_claims.duplicate(true),
			"awards": store._claim_awards.duplicate(true),
			"discarded_cards": [],
		},
	]
	store.publish()
	await process_frame
	await process_frame

	var reveal_list := screen.find_child("ClaimRevealList", true, false) as VBoxContainer
	_expect(reveal_list != null and reveal_list.get_child_count() == 3, "三名非行动者的选择同时揭晓")
	var reveal_text := _node_text(screen.find_child("PlayedCombinationPanel", true, false))
	_expect(reveal_text.contains("乙") and reveal_text.contains("独得"), "唯一抢牌显示参与者和原牌")
	_expect(reveal_text.contains("机器人丙") and reveal_text.contains("撞车"), "撞车显示参与者和盲抽结果")
	_expect(reveal_text.contains("K") and reveal_text.contains("Q"), "撞车结果显示实际获得牌")
	var history_text := _node_text(screen._history_list)
	_expect(history_text.contains("第 1 回合 · 抢牌揭晓"), "历史保留旧抢牌回合")
	_expect(history_text.contains("不抢 +1 分"), "历史记录 Pass 得分")
	_expect(history_text.contains("弃置"), "历史记录公共弃牌")
	_expect(history_text.contains("第 2 回合 · 抢牌揭晓"), "历史追加当前抢牌结果")


func _test_collision_outcome_moves_once_without_resizing(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	var next_event: Dictionary = store._claim_events[1].duplicate(true)
	next_event["turn_number"] = 3
	store._claim_events.append(next_event)
	store.turn_number = 3
	store.publish()

	var unique_row := screen.find_child("ClaimOutcomeSeat1", true, false) as Label
	var collision_row := screen.find_child("ClaimOutcomeSeat2", true, false) as Label
	if unique_row == null or collision_row == null:
		_failures.append("抢牌揭晓应提供稳定的席位结果行")
		return
	_expect(is_equal_approx(unique_row.scale.x, 1.0), "独得结果不播放撞车动效")
	_expect(collision_row.scale.x >= 0.94 and collision_row.scale.x < 1.0, "撞车结果播放克制的一次性动效")
	await process_frame
	var layout_size := collision_row.size
	await create_timer(0.3).timeout
	_expect(is_equal_approx(collision_row.scale.x, 1.0), "撞车动效短暂并归位")
	_expect_equal(collision_row.size, layout_size, "撞车动效不改变布局尺寸")
	store.publish()
	await process_frame
	await process_frame
	var refreshed_collision := screen.find_child("ClaimOutcomeSeat2", true, false) as Label
	_expect(refreshed_collision != null and is_equal_approx(refreshed_collision.scale.x, 1.0), "同回合状态更新不重播撞车动效")
	_expect(refreshed_collision != null and refreshed_collision.size == layout_size, "重复刷新不改变撞车行布局")


func _test_new_room_replays_collision_motion(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	store.room_id = "room-b"
	store.publish()
	var collision_row := screen.find_child("ClaimOutcomeSeat2", true, false) as Label
	_expect(
		collision_row != null and collision_row.scale.x >= 0.94 and collision_row.scale.x < 1.0,
		"新房间的相同回合重新播放撞车动效"
	)
	await create_timer(0.3).timeout


func _test_public_history_is_chronological(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	for turn_number in [2, 3]:
		var play_event: Dictionary = store._play_events[0].duplicate(true)
		play_event["turn_number"] = turn_number
		store._play_events.append(play_event)
	store.publish()
	await process_frame
	await process_frame

	var item_names: Array[String] = []
	for item in screen._history_list.get_children():
		item_names.append(item.name)
	_expect_equal(item_names, [
		"ContestRound0",
		"ContestRound1",
		"PlayEvent1",
		"ClaimEvent1",
		"PlayEvent2",
		"ClaimEvent2",
		"PlayEvent3",
		"ClaimEvent3",
	], "公共历史按回合交错显示出牌与抢牌揭晓")


func _test_rejected_claim_reenables_controls_without_moving_layout(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	store.phase = "actor_play"
	store.actor_seat_index = 0
	store.claim_committed = false
	store.claim_card_id = null
	store.private_state_changed.emit()
	store.publish()
	await process_frame
	await process_frame
	store.phase = "claim_commit"
	store.actor_seat_index = 1
	store.turn_number = 4
	store._played_cards = [
		_card("retry-queen", 12, "hearts", 0),
		_card("retry-king", 13, "hearts", 0),
		_card("retry-ace", 14, "hearts", 0),
	]
	store.publish()
	await process_frame
	await process_frame

	var first_card := screen.find_child("ClaimCard0", true, false) as Button
	var submit_button := screen.find_child("SubmitClaimButton", true, false) as Button
	var pass_button := screen.find_child("PassClaimButton", true, false) as Button
	if first_card == null or submit_button == null or pass_button == null:
		_failures.append("抢牌重试测试缺少稳定控件")
		return
	first_card.button_pressed = true
	submit_button.pressed.emit()
	var action_rect_before := screen._action_bar.get_global_rect()
	var pass_rect_before := pass_button.get_global_rect()
	store.action_failed.emit("invalid_claim", "该牌已不能抢，请重新选择")
	await process_frame
	await process_frame

	var refreshed_first := screen.find_child("ClaimCard0", true, false) as Button
	_expect(refreshed_first != null and not refreshed_first.disabled, "抢牌失败后重新启用公开牌")
	_expect(refreshed_first != null and not refreshed_first.button_pressed, "抢牌失败后清空旧选择")
	_expect(not pass_button.disabled, "抢牌失败后可以改为不抢")
	_expect(submit_button.disabled, "清空旧选择后等待重新选牌")
	_expect(screen._action_error_label.text.contains("请重新选择"), "抢牌失败原因保持可见")
	_expect_equal(screen._action_bar.get_global_rect(), action_rect_before, "抢牌失败不移动行动栏")
	_expect_equal(pass_button.get_global_rect(), pass_rect_before, "抢牌失败不移动 Pass 按钮")
	refreshed_first.button_pressed = true
	_expect(not submit_button.disabled, "抢牌失败后可以重新选择并提交")
	store.actor_seat_index = 0
	store.publish()
	await process_frame
	await process_frame


func _test_action_error_is_visible_without_moving_controls(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	var error_label := screen.find_child("ActionErrorLabel", true, false) as Label
	if error_label == null:
		_failures.append("比赛界面应提供稳定的操作错误区域")
		return
	var play_button := screen.find_child("PlayCardsButton", true, false) as Button
	var action_rect_before := screen._action_bar.get_global_rect()
	var play_rect_before := play_button.get_global_rect()
	store.action_failed.emit("invalid_cards", "请选择恰好三张不同且仍在手牌中的牌")
	await process_frame
	await process_frame

	_expect(error_label.text.contains("请选择恰好三张"), "定向操作错误在行动栏可见")
	_expect_equal(screen._action_bar.get_global_rect(), action_rect_before, "错误文本不改变行动栏边界")
	_expect_equal(play_button.get_global_rect(), play_rect_before, "错误文本不移动出牌按钮")
	var error_rect := error_label.get_global_rect()
	var action_rect := screen._action_bar.get_global_rect()
	_expect(error_rect.position.x >= action_rect.position.x, "错误文本不越出行动栏左侧")
	_expect(error_rect.end.x <= action_rect.end.x, "错误文本不越出行动栏右侧")
	_expect(not error_rect.intersects(play_button.get_global_rect()), "错误文本不遮挡出牌按钮")


func _test_unbinding_store_clears_pending_claim_controls(
	screen: MatchScreen,
	store: FakeMatchStore
) -> void:
	store.phase = "claim_commit"
	store.actor_seat_index = 1
	store.claim_committed = false
	store.claim_card_id = null
	store._played_cards = [
		_card("unbind-queen", 12, "hearts", 0),
		_card("unbind-king", 13, "hearts", 0),
		_card("unbind-ace", 14, "hearts", 0),
	]
	store.publish()
	await process_frame
	await process_frame
	var first_card := screen.find_child("ClaimCard0", true, false) as Button
	var submit_button := screen.find_child("SubmitClaimButton", true, false) as Button
	var pass_button := screen.find_child("PassClaimButton", true, false) as Button
	if first_card == null or submit_button == null or pass_button == null:
		_failures.append("解绑回归测试缺少抢牌控件")
		return
	first_card.button_pressed = true
	submit_button.pressed.emit()
	_expect(first_card.disabled and pass_button.disabled, "解绑前处于抢牌 pending")

	screen.set_match_store(null)
	await process_frame
	await process_frame
	_expect(not submit_button.visible and not pass_button.visible, "解除状态源后隐藏抢牌按钮")
	_expect(not screen._played_panel.visible, "解除状态源后隐藏公开抢牌区域")
	screen.set_match_store(store)
	await process_frame
	await process_frame
	var rebound_first := screen.find_child("ClaimCard0", true, false) as Button
	_expect(rebound_first != null and not rebound_first.disabled, "重新绑定后清除旧 pending")
	_expect(rebound_first != null and not rebound_first.button_pressed, "重新绑定后清除旧抢牌选择")
	_expect(pass_button.visible and not pass_button.disabled, "重新绑定后 Pass 恢复可用")
	_expect(submit_button.disabled, "重新绑定后等待新的选牌")
	store.actor_seat_index = 0
	store.publish()
	await process_frame
	await process_frame


func _test_key_regions_do_not_overlap(screen: MatchScreen, viewport_size: Vector2) -> void:
	var header_rect := screen._header.get_global_rect()
	var history_rect := screen._history_panel.get_global_rect()
	var table_rect := screen._table_area.get_global_rect()
	var hand_rect := screen._hand_panel.get_global_rect()
	var action_rect := screen._action_bar.get_global_rect()
	var contest_rect := screen._contest_panel.get_global_rect()
	var played_panel := screen.find_child("PlayedCombinationPanel", true, false) as PanelContainer
	_expect(not header_rect.intersects(history_rect), "顶栏与历史区不重叠")
	_expect(not header_rect.intersects(table_rect), "顶栏与牌桌不重叠")
	_expect(history_rect.position.x >= 0.0 and history_rect.end.x <= viewport_size.x, "历史区横向在视口内")
	_expect(table_rect.position.x >= 0.0 and table_rect.end.x <= viewport_size.x, "牌桌横向在视口内")
	_expect(hand_rect.position.y >= table_rect.position.y, "手牌区在牌桌内")
	_expect(hand_rect.end.y <= table_rect.end.y, "手牌区不越出牌桌")
	_expect(hand_rect.position.y > table_rect.position.y + table_rect.size.y * 0.5, "手牌区贴近牌桌底部")
	_expect(not hand_rect.intersects(contest_rect), "手牌区不遮挡中央拼点")
	if played_panel != null and played_panel.visible:
		var played_rect := played_panel.get_global_rect()
		_expect(not hand_rect.intersects(played_rect), "手牌区不遮挡公开出牌")
		for card_control in screen.find_child("PlayedCardsRow", true, false).get_children():
			_expect(card_control.get_global_rect().end.x <= played_rect.end.x, "公开出牌不被裁出")
	for seat_panel in screen._seat_cards:
		_expect(not hand_rect.intersects(seat_panel.get_global_rect()), "手牌区不遮挡参与者席位")
	_expect(action_rect.position.y >= hand_rect.position.y, "行动栏在手牌区内")
	_expect(action_rect.end.y <= hand_rect.end.y, "行动栏不越出手牌区")


func _selected_card_count(screen: MatchScreen) -> int:
	var count := 0
	for index in range(screen._hand_cards.size()):
		var card_control: Variant = screen.find_child("HandCard%d" % index, true, false)
		if card_control is Button and card_control.button_pressed:
			count += 1
	return count


func _seat(
	seat_index: int,
	participant_id: String,
	nickname: String,
	is_bot: bool,
	score: int,
	hand_count: int
) -> Dictionary:
	return {
		"seat_index": seat_index,
		"participant_id": participant_id,
		"nickname": nickname,
		"is_bot": is_bot,
		"is_ready": true,
		"score": score,
		"hand_count": hand_count,
	}


func _card(card_id: String, rank: int, suit: String, copy_index: int) -> Dictionary:
	return {
		"id": card_id,
		"rank": rank,
		"suit": suit,
		"copy_index": copy_index,
	}


func _node_text(node: Node) -> String:
	var text := ""
	if node is Label:
		text += (node as Label).text
	for child in node.get_children():
		text += _node_text(child)
	return text


func _expect(condition: bool, context: String) -> void:
	if not condition:
		_failures.append(context)


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
