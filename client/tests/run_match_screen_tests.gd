extends SceneTree

const MatchScreen = preload("res://scripts/match/match_screen.gd")

var _failures: Array[String] = []


class FakeMatchStore extends RefCounted:
	signal state_changed()
	signal private_state_changed()

	var phase := "actor_play"
	var actor_seat_index := 2
	var draw_pile_count := 20
	var local_participant_id := "human-a"
	var _participants: Array[Dictionary] = []
	var _contest_rounds: Array[Dictionary] = []
	var _local_hand: Array[Dictionary] = []

	func get_participants() -> Array[Dictionary]:
		return _participants

	func get_contest_rounds() -> Array[Dictionary]:
		return _contest_rounds

	func get_local_hand() -> Array[Dictionary]:
		return _local_hand

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

	_test_four_seats_are_visible(screen)
	_test_public_header_and_contest_history_are_visible(screen)
	_expect_equal(screen._hand_cards.size(), 0, "拼点展示期间尚未收到私有手牌")
	for rank in [2, 5, 8, 11, 12, 13, 14, 10]:
		store._local_hand.append(_card("local-%s" % rank, rank, "hearts" if rank >= 11 else "clubs", 0))
	store.private_state_changed.emit()
	await process_frame
	await process_frame
	_test_local_hand_is_readable_and_private(screen)
	_test_key_regions_do_not_overlap(screen)
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


func _test_four_seats_are_visible(screen: MatchScreen) -> void:
	_expect_equal(screen._seat_cards.size(), 4, "固定四席")
	for index in range(4):
		var rect := screen._seat_cards[index].get_global_rect()
		_expect(rect.size.x >= 140.0 and rect.size.y >= 50.0, "席位 %d 尺寸稳定" % index)
		_expect(rect.position.x >= 0.0 and rect.position.y >= 0.0, "席位 %d 不越出左上边界" % index)
		_expect(rect.end.x <= 960.0 and rect.end.y <= 540.0, "席位 %d 不越出视口" % index)
	_expect(screen._seat_name_labels[0].text == "甲", "本地参与者昵称可见")
	_expect(screen._seat_name_labels[2].text == "机器人丙", "机器人昵称可见")
	_expect(screen._seat_role_labels[2].text.contains("行动中"), "行动者高亮")


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


func _test_key_regions_do_not_overlap(screen: MatchScreen) -> void:
	var header_rect := screen._header.get_global_rect()
	var history_rect := screen._history_panel.get_global_rect()
	var table_rect := screen._table_area.get_global_rect()
	var hand_rect := screen._hand_panel.get_global_rect()
	var action_rect := screen._action_bar.get_global_rect()
	var contest_rect := screen._contest_panel.get_global_rect()
	_expect(not header_rect.intersects(history_rect), "顶栏与历史区不重叠")
	_expect(not header_rect.intersects(table_rect), "顶栏与牌桌不重叠")
	_expect(history_rect.position.x >= 0.0 and history_rect.end.x <= 960.0, "历史区横向在视口内")
	_expect(table_rect.position.x >= 0.0 and table_rect.end.x <= 960.0, "牌桌横向在视口内")
	_expect(hand_rect.position.y >= table_rect.position.y, "手牌区在牌桌内")
	_expect(hand_rect.end.y <= table_rect.end.y, "手牌区不越出牌桌")
	_expect(hand_rect.position.y > table_rect.position.y + table_rect.size.y * 0.5, "手牌区贴近牌桌底部")
	_expect(not hand_rect.intersects(contest_rect), "手牌区不遮挡中央拼点")
	for seat_panel in screen._seat_cards:
		_expect(not hand_rect.intersects(seat_panel.get_global_rect()), "手牌区不遮挡参与者席位")
	_expect(action_rect.position.y >= hand_rect.position.y, "行动栏在手牌区内")
	_expect(action_rect.end.y <= hand_rect.end.y, "行动栏不越出手牌区")


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
