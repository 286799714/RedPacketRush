extends SceneTree

const FakeRealtimeAdapter = preload("res://tests/fakes/fake_realtime_adapter.gd")
const MatchStore = preload("res://scripts/match/match_store.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_started_snapshot_activates_match_once()
	_test_deck_mode_follows_room_snapshot_and_resets_on_leave()
	_test_public_collections_are_sanitized_deep_copies()
	_test_public_play_state_is_retained_deep_copied_and_cleared()
	_test_public_claim_progress_is_not_retained()
	_test_public_claim_event_history_is_retained_deep_copied_and_cleared()
	_test_public_discard_state_is_retained_deep_copied_and_cleared()
	_test_public_final_settlement_is_retained_deep_copied_and_cleared()
	_test_play_cards_intention_is_forwarded_without_optimistic_state()
	_test_claim_intention_is_forwarded_without_optimistic_state()
	_test_discard_intention_is_forwarded_without_optimistic_state()
	_test_final_selection_intentions_are_forwarded_without_optimistic_state()
	_test_only_targeted_private_hand_is_retained()
	_test_only_targeted_private_claim_confirmation_is_retained()
	_test_only_targeted_private_final_confirmation_is_retained()
	_test_room_errors_and_connection_changes_are_exposed()
	_test_leave_clears_match_and_allows_next_room_activation()

	if _failures.is_empty():
		print("PASS: match store tests")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_started_snapshot_activates_match_once() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	var observed := {"activation_count": 0, "state_change_count": 0}
	match_store.match_activated.connect(func(): observed["activation_count"] += 1)
	match_store.state_changed.connect(func(): observed["state_change_count"] += 1)

	adapter.publish_game_room_state(_started_snapshot("room-a", "human-a", 20))

	_expect_equal(match_store.room_id, "room-a", "房间标识")
	_expect_equal(match_store.local_participant_id, "human-a", "本地参与者")
	_expect_equal(match_store.status, "started", "房间状态")
	_expect_equal(match_store.phase, "actor_play", "比赛阶段")
	_expect_equal(match_store.actor_seat_index, 2, "当前行动席位")
	_expect_equal(match_store.draw_pile_count, 20, "牌堆数量")
	_expect_equal(match_store.get_participants().size(), 4, "四名参与者")
	_expect_equal(match_store.get_contest_rounds().size(), 1, "拼点历史")
	_expect_equal(observed["activation_count"], 1, "首次启动激活一次")
	_expect_equal(observed["state_change_count"], 1, "公共状态通知")

	adapter.publish_game_room_state(_started_snapshot("room-a", "human-a", 19))

	_expect_equal(match_store.draw_pile_count, 19, "后续公共状态更新")
	_expect_equal(observed["activation_count"], 1, "同一房间不重复激活")
	_expect_equal(observed["state_change_count"], 2, "每个公共快照均通知")


func _test_deck_mode_follows_room_snapshot_and_resets_on_leave() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	var snapshot := _started_snapshot("room-a", "human-a", 72)
	snapshot["deck_mode"] = "two"
	adapter.publish_game_room_state(snapshot)

	var has_deck_mode := false
	for property in match_store.get_property_list():
		if str(property.get("name", "")) == "deck_mode":
			has_deck_mode = true
			break
	if not has_deck_mode:
		_failures.append("MatchStore 应公开当前牌组模式")
		return
	_expect_equal(match_store.get("deck_mode"), "two", "保存两副牌模式")

	adapter.publish_game_room_left(4000, "主动离开")
	_expect_equal(match_store.get("deck_mode"), "one", "离房重置为一副牌模式")


func _test_public_collections_are_sanitized_deep_copies() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	var snapshot := _started_snapshot("room-a", "human-a", 20)
	snapshot["seats"][0]["hand"] = [_card("leaked", 13, "clubs", 0)]
	snapshot["seats"][0]["transport_only"] = "不可见"
	adapter.publish_game_room_state(snapshot)

	var participants := match_store.get_participants()
	_expect_equal(participants[0].keys(), [
		"seat_index",
		"participant_id",
		"nickname",
		"is_bot",
		"is_ready",
		"score",
		"hand_count",
	], "参与者字段白名单")
	participants[0]["nickname"] = "被篡改"
	participants.clear()
	_expect_equal(match_store.get_participants().size(), 4, "参与者数组深拷贝")
	_expect_equal(match_store.get_participants()[0]["nickname"], "甲", "参与者字典深拷贝")

	var contest_rounds := match_store.get_contest_rounds()
	contest_rounds[0]["reveals"][0]["card"]["rank"] = 2
	contest_rounds.clear()
	_expect_equal(match_store.get_contest_rounds().size(), 1, "拼点数组深拷贝")
	_expect_equal(
		match_store.get_contest_rounds()[0]["reveals"][0]["card"]["rank"],
		14,
		"拼点嵌套字典深拷贝"
	)


func _test_public_play_state_is_retained_deep_copied_and_cleared() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	if not match_store.has_method("get_played_cards") or not match_store.has_method("get_play_events"):
		_failures.append("MatchStore 应公开已出牌和历史事件的只读副本")
		return
	var snapshot := _started_snapshot("room-a", "human-a", 17)
	snapshot["phase"] = "claim_commit"
	snapshot["turn_number"] = 1
	snapshot["played_cards"] = [
		_card("play-queen", 12, "hearts", 0),
		_card("play-king", 13, "hearts", 0),
		_card("play-ace", 14, "hearts", 0),
	]
	snapshot["played_category"] = "straight_flush"
	snapshot["played_score"] = 10
	snapshot["play_events"] = [{
		"turn_number": 1,
		"actor_seat_index": 0,
		"cards": snapshot["played_cards"].duplicate(true),
		"category": "straight_flush",
		"score": 10,
	}]

	adapter.publish_game_room_state(snapshot)

	_expect_equal(match_store.turn_number, 1, "保存回合编号")
	_expect_equal(match_store.played_category, "straight_flush", "保存公开牌型")
	_expect_equal(match_store.played_score, 10, "保存公开出牌得分")
	var returned_cards: Array[Dictionary] = match_store.get_played_cards()
	returned_cards[0]["rank"] = 2
	returned_cards.clear()
	_expect_equal(match_store.get_played_cards(), snapshot["played_cards"], "公开出牌深拷贝")
	var returned_events: Array[Dictionary] = match_store.get_play_events()
	returned_events[0]["cards"][0]["rank"] = 2
	returned_events.clear()
	_expect_equal(match_store.get_play_events(), snapshot["play_events"], "出牌历史嵌套深拷贝")

	adapter.publish_game_room_state(_started_snapshot("room-a", "human-a", 17))

	_expect_equal(match_store.get_played_cards(), [], "新回合快照清空旧出牌")
	_expect_equal(match_store.get_play_events(), [], "空历史快照清空旧出牌事件")
	_expect_equal(match_store.played_category, "", "新回合快照清空旧牌型")
	_expect_equal(match_store.played_score, 0, "新回合快照清空旧得分")


func _test_public_claim_progress_is_not_retained() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	var snapshot := _started_snapshot("room-a", "human-a", 17)
	snapshot["phase"] = "claim_commit"
	snapshot["claim_commit_count"] = 2
	adapter.publish_game_room_state(snapshot)

	for property in match_store.get_property_list():
		if str(property.get("name", "")) == "claim_commit_count":
			_failures.append("MatchStore 不应公开抢牌提交进度")
			return


func _test_public_claim_event_history_is_retained_deep_copied_and_cleared() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	if not match_store.has_method("get_claim_events"):
		_failures.append("MatchStore 应公开抢牌结果历史的只读副本")
		return
	var snapshot := _started_snapshot("room-a", "human-a", 17)
	snapshot["claim_events"] = [{
		"turn_number": 2,
		"claims": [
			{"seat_index": 1, "card_id": "played-ace"},
			{"seat_index": 2, "card_id": "played-queen"},
			{"seat_index": 3, "card_id": null},
		],
		"awards": [
			{"seat_index": 1, "card": _card("played-ace", 14, "hearts", 0), "source": "unique"},
			{"seat_index": 2, "card": _card("collision-king", 13, "hearts", 0), "source": "collision"},
		],
		"discarded_cards": [_card("discarded-queen", 12, "hearts", 0)],
	}]
	adapter.publish_game_room_state(snapshot)

	var returned_events: Array[Dictionary] = match_store.get_claim_events()
	returned_events[0]["claims"][0]["card_id"] = "tampered"
	returned_events[0]["awards"][0]["card"]["rank"] = 2
	returned_events[0]["discarded_cards"].clear()
	_expect_equal(match_store.get_claim_events(), snapshot["claim_events"], "抢牌结果历史嵌套深拷贝")

	adapter.publish_game_room_state(_started_snapshot("room-b", "human-z", 18))
	_expect_equal(match_store.get_claim_events(), [], "新房间快照清空旧抢牌历史")


func _test_public_discard_state_is_retained_deep_copied_and_cleared() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	for method_name in [
		"get_pending_discard_seat_indexes",
		"get_discard_events",
	]:
		if not match_store.has_method(method_name):
			_failures.append("MatchStore 应公开 %s 的只读副本" % method_name)
			return
	var discarded_card := _card("original-clubs-2", 2, "clubs", 0)
	var snapshot := _started_snapshot("room-a", "human-a", 17)
	snapshot["phase"] = "award_discard"
	snapshot["pending_discard_seat_indexes"] = [0, 2]
	snapshot["sealed_card_count"] = 2
	snapshot["discard_events"] = [{
		"turn_number": 2,
		"seat_index": 2,
		"card": discarded_card,
	}]
	adapter.publish_game_room_state(snapshot)

	var returned_pending: Array[int] = match_store.get_pending_discard_seat_indexes()
	returned_pending.clear()
	_expect_equal(match_store.get_pending_discard_seat_indexes(), [0, 2], "待弃牌席位深拷贝")
	_expect_equal(match_store.sealed_card_count, 2, "保存公开封存牌数量")
	var returned_events: Array[Dictionary] = match_store.get_discard_events()
	returned_events[0]["card"]["rank"] = 14
	returned_events.clear()
	_expect_equal(match_store.get_discard_events(), snapshot["discard_events"], "弃牌事件嵌套深拷贝")

	adapter.publish_game_room_state(_started_snapshot("room-b", "human-z", 18))
	_expect_equal(match_store.get_pending_discard_seat_indexes(), [], "新回合快照清空待弃牌席位")
	_expect_equal(match_store.sealed_card_count, 0, "新房间快照清空封存牌数量")
	_expect_equal(match_store.get_discard_events(), [], "新房间快照清空弃牌事件")


func _test_public_final_settlement_is_retained_deep_copied_and_cleared() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	for method_name in ["get_final_results", "get_winner_seat_indexes", "get_final_events"]:
		if not match_store.has_method(method_name):
			_failures.append("MatchStore 应公开 %s 的只读副本" % method_name)
			return
	var result := {
		"seat_index": 0,
		"groups": [
			{
				"cards": [
					_card("hearts-q", 12, "hearts", 0),
					_card("hearts-k", 13, "hearts", 0),
					_card("hearts-a", 14, "hearts", 0),
				],
				"category": "straight_flush",
				"score": 10,
			},
			{
				"cards": [
					_card("clubs-2", 2, "clubs", 0),
					_card("spades-2", 2, "spades", 0),
					_card("diamonds-7", 7, "diamonds", 0),
				],
				"category": "pair",
				"score": 2,
			},
		],
		"total_score": 22,
	}
	var event := {
		"type": "final_settlement",
		"results": [result],
		"winner_seat_indexes": [0],
	}
	var snapshot := _started_snapshot("room-a", "human-a", 0)
	snapshot["phase"] = "final_reveal"
	snapshot["final_results"] = [result]
	snapshot["winner_seat_indexes"] = [0]
	snapshot["final_events"] = [event]
	snapshot["final_committed"] = true
	snapshot["final_groups"] = [["forged-a", "forged-b", "forged-c"]]
	adapter.publish_game_room_state(snapshot)

	var returned_results: Array[Dictionary] = match_store.get_final_results()
	returned_results[0]["groups"][0]["cards"][0]["rank"] = 2
	returned_results.clear()
	_expect_equal(match_store.get_final_results(), [result], "终局结果嵌套深拷贝")
	var returned_winners: Array[int] = match_store.get_winner_seat_indexes()
	returned_winners.clear()
	_expect_equal(match_store.get_winner_seat_indexes(), [0], "共同胜者席位深拷贝")
	var returned_events: Array[Dictionary] = match_store.get_final_events()
	returned_events[0]["results"].clear()
	returned_events.clear()
	_expect_equal(match_store.get_final_events(), [event], "终局事件嵌套深拷贝")
	_expect_equal(match_store.get("final_committed"), false, "公共快照不能确认本地最终选择")
	_expect_equal(match_store.get_final_groups(), [], "公共快照不能写入本地最终分组")

	adapter.publish_game_room_left(4000, "主动离开")
	_expect_equal(match_store.get_final_results(), [], "离房清空终局结果")
	_expect_equal(match_store.get_winner_seat_indexes(), [], "离房清空共同胜者")
	_expect_equal(match_store.get_final_events(), [], "离房清空终局事件")


func _test_play_cards_intention_is_forwarded_without_optimistic_state() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	if not match_store.has_method("play_cards"):
		_failures.append("MatchStore 应公开 play_cards 意图")
		return
	adapter.publish_game_room_state(_started_snapshot("room-a", "human-a", 20))
	var local_hand := [
		_card("local-2", 2, "clubs", 0),
		_card("local-3", 3, "clubs", 0),
		_card("local-4", 4, "clubs", 0),
	]
	adapter.publish_match_private_state({
		"participant_id": "human-a",
		"hand": local_hand,
	})
	var selected_card_ids: Array[String] = ["local-2", "local-3", "local-4"]

	match_store.play_cards(selected_card_ids)

	_expect_equal(adapter.room_requests, [{
		"type": "play_cards",
		"payload": {"cardIds": ["local-2", "local-3", "local-4"]},
	}], "出牌意图转发到 adapter")
	_expect_equal(match_store.get_local_hand(), local_hand, "发送后等待权威私有手牌")
	_expect_equal(match_store.get_played_cards(), [], "发送后等待权威公开出牌")
	_expect_equal(match_store.played_score, 0, "发送后不乐观加分")


func _test_claim_intention_is_forwarded_without_optimistic_state() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	if not match_store.has_method("claim_card"):
		_failures.append("MatchStore 应公开 claim_card 意图")
		return
	var snapshot := _started_snapshot("room-a", "human-a", 17)
	snapshot["phase"] = "claim_commit"
	snapshot["actor_seat_index"] = 2
	snapshot["played_cards"] = [
		_card("played-queen", 12, "hearts", 0),
		_card("played-king", 13, "hearts", 0),
		_card("played-ace", 14, "hearts", 0),
	]
	adapter.publish_game_room_state(snapshot)

	match_store.claim_card("played-ace")
	match_store.claim_card(null)

	_expect_equal(adapter.room_requests, [
		{"type": "claim", "payload": {"cardId": "played-ace"}},
		{"type": "claim", "payload": {"cardId": null}},
	], "抢牌与不抢意图转发到 adapter")
	_expect_equal(match_store.get_played_cards(), snapshot["played_cards"], "发送后等待权威抢牌揭晓")
	_expect_equal(match_store.phase, "claim_commit", "发送后不乐观推进阶段")


func _test_discard_intention_is_forwarded_without_optimistic_state() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	if not match_store.has_method("discard_card"):
		_failures.append("MatchStore 应公开 discard_card 意图")
		return
	var snapshot := _started_snapshot("room-a", "human-a", 17)
	snapshot["phase"] = "award_discard"
	snapshot["pending_discard_seat_indexes"] = [0]
	adapter.publish_game_room_state(snapshot)
	var hand: Array[Dictionary] = []
	for rank in range(2, 11):
		hand.append(_card("local-%d" % rank, rank, "clubs", 0))
	adapter.publish_match_private_state({
		"participant_id": "human-a",
		"hand": hand,
	})

	match_store.discard_card("local-2", 2)

	_expect_equal(adapter.room_requests, [{
		"type": "discard",
		"payload": {"cardId": "local-2", "turnNumber": 2},
	}], "弃牌意图转发到 adapter")
	_expect_equal(match_store.get_local_hand(), hand, "发送后等待权威私有手牌")
	_expect_equal(match_store.get_pending_discard_seat_indexes(), [0], "发送后等待权威待弃席位")
	_expect_equal(match_store.phase, "award_discard", "发送后不乐观推进阶段")


func _test_final_selection_intentions_are_forwarded_without_optimistic_state() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	if (
		not match_store.has_method("submit_final_selection")
		or not match_store.has_method("submit_best_final_selection")
	):
		_failures.append("MatchStore 应公开手动与最佳最终选择意图")
		return
	var snapshot := _started_snapshot("room-a", "human-a", 0)
	snapshot["phase"] = "final_commit"
	adapter.publish_game_room_state(snapshot)
	adapter.publish_match_private_state({
		"participant_id": "human-a",
		"hand": [],
		"final_committed": false,
		"final_groups": [],
	})
	var groups := [
		["clubs-2", "clubs-3", "clubs-4"],
		["hearts-q", "hearts-k", "hearts-a"],
	]

	match_store.submit_final_selection(groups)
	match_store.submit_best_final_selection()

	_expect_equal(adapter.room_requests, [
		{
			"type": "final_selection",
			"payload": {"mode": "manual", "groups": groups},
		},
		{
			"type": "final_selection",
			"payload": {"mode": "best"},
		},
	], "最终选择意图转发到 adapter")
	_expect_equal(match_store.final_committed, false, "发送后等待权威最终确认")
	_expect_equal(match_store.get_final_groups(), [], "发送后不乐观写入最终分组")
	_expect_equal(match_store.get_final_results(), [], "发送后不乐观生成终局结果")
	_expect_equal(match_store.phase, "final_commit", "发送后不乐观推进最终阶段")


func _test_only_targeted_private_hand_is_retained() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	var observed := {"private_change_count": 0}
	match_store.private_state_changed.connect(func(): observed["private_change_count"] += 1)
	var public_snapshot := _started_snapshot("room-a", "human-a", 20)
	public_snapshot["hand"] = [_card("public-hand", 14, "hearts", 0)]
	public_snapshot["hands"] = {"human-a": [_card("public-hands", 13, "diamonds", 0)]}
	public_snapshot["private_claim"] = {"card_id": "public-claim"}
	adapter.publish_game_room_state(public_snapshot)

	_expect_equal(match_store.get_local_hand(), [], "公共快照不能写入私有手牌")
	adapter.publish_match_private_state({
		"participant_id": "human-b",
		"hand": [_card("other-card", 12, "spades", 0)],
	})
	_expect_equal(match_store.get_local_hand(), [], "忽略其他参与者私信")
	_expect_equal(observed["private_change_count"], 0, "忽略私信不通知")

	var local_card := _card("local-card", 11, "clubs", 0)
	adapter.publish_match_private_state({
		"participant_id": "human-a",
		"hand": [local_card],
	})
	_expect_equal(match_store.get_local_hand(), [local_card], "接收本地完整手牌")
	_expect_equal(observed["private_change_count"], 1, "本地私信通知")
	var returned_hand := match_store.get_local_hand()
	returned_hand[0]["rank"] = 2
	returned_hand.clear()
	_expect_equal(match_store.get_local_hand(), [local_card], "本地手牌深拷贝")


func _test_only_targeted_private_claim_confirmation_is_retained() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	var public_snapshot := _started_snapshot("room-a", "human-a", 17)
	public_snapshot["phase"] = "claim_commit"
	public_snapshot["claim_committed"] = true
	public_snapshot["claim_card_id"] = "public-leak"
	adapter.publish_game_room_state(public_snapshot)

	_expect_equal(match_store.get("claim_committed"), false, "公共快照不能确认本地抢牌")
	_expect_equal(match_store.get("claim_card_id"), null, "公共快照不能写入本地抢牌选择")
	adapter.publish_match_private_state({
		"participant_id": "human-b",
		"hand": [],
		"claim_committed": true,
		"claim_card_id": "other-choice",
	})
	_expect_equal(match_store.get("claim_committed"), false, "忽略其他参与者抢牌确认")

	adapter.publish_match_private_state({
		"participant_id": "human-a",
		"hand": [],
		"claim_committed": true,
		"claim_card_id": "played-ace",
	})
	_expect_equal(match_store.get("claim_committed"), true, "保存本地定向抢牌确认")
	_expect_equal(match_store.get("claim_card_id"), "played-ace", "保存本地定向抢牌选择")

	adapter.publish_match_private_state({
		"participant_id": "human-a",
		"hand": [],
		"claim_committed": false,
		"claim_card_id": null,
	})
	_expect_equal(match_store.get("claim_committed"), false, "权威私信重置抢牌确认")
	_expect_equal(match_store.get("claim_card_id"), null, "权威私信清空抢牌选择")


func _test_only_targeted_private_final_confirmation_is_retained() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	adapter.publish_game_room_state(_started_snapshot("room-a", "human-a", 0))
	var groups := [
		["clubs-2", "clubs-3", "clubs-4"],
		["hearts-q", "hearts-k", "hearts-a"],
	]
	adapter.publish_match_private_state({
		"participant_id": "human-b",
		"hand": [],
		"final_committed": true,
		"final_groups": groups,
	})
	_expect_equal(match_store.final_committed, false, "忽略其他参与者最终确认")
	_expect_equal(match_store.get_final_groups(), [], "忽略其他参与者最终分组")

	adapter.publish_match_private_state({
		"participant_id": "human-a",
		"hand": [],
		"final_committed": true,
		"final_groups": groups,
	})
	_expect_equal(match_store.final_committed, true, "保存本地定向最终确认")
	var returned_groups: Array = match_store.get_final_groups()
	returned_groups[0][0] = "tampered"
	returned_groups.clear()
	_expect_equal(match_store.get_final_groups(), groups, "本地最终分组嵌套深拷贝")

	adapter.publish_match_private_state({
		"participant_id": "human-a",
		"hand": [],
		"final_committed": false,
		"final_groups": [],
	})
	_expect_equal(match_store.final_committed, false, "权威私信重置最终确认")
	_expect_equal(match_store.get_final_groups(), [], "权威私信清空最终分组")


func _test_room_errors_and_connection_changes_are_exposed() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	var observed := {"error": {}, "connection": {}}
	if not match_store.has_signal("action_failed") or not match_store.has_signal("connection_changed"):
		_failures.append("MatchStore 应公开操作错误和连接状态信号")
		return
	match_store.action_failed.connect(func(code: String, message: String):
		observed["error"] = {"code": code, "message": message}
	)
	match_store.connection_changed.connect(func(state: String, detail: String):
		observed["connection"] = {"state": state, "detail": detail}
	)

	adapter.publish_room_error("wrong_phase", "当前阶段不能执行此操作")
	adapter.publish_game_room_connection_state("reconnecting", "网络中断")

	_expect_equal(observed["error"], {
		"code": "wrong_phase",
		"message": "当前阶段不能执行此操作",
	}, "定向操作错误")
	_expect_equal(observed["connection"], {
		"state": "reconnecting",
		"detail": "网络中断",
	}, "比赛房间连接状态")


func _test_leave_clears_match_and_allows_next_room_activation() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var match_store := MatchStore.new(adapter)
	var observed := {
		"activation_count": 0,
		"state_change_count": 0,
		"private_change_count": 0,
		"left": {},
	}
	if not match_store.has_signal("left"):
		_failures.append("MatchStore 应公开离开信号")
		return
	match_store.match_activated.connect(func(): observed["activation_count"] += 1)
	match_store.state_changed.connect(func(): observed["state_change_count"] += 1)
	match_store.private_state_changed.connect(func(): observed["private_change_count"] += 1)
	match_store.left.connect(func(code: int, reason: String):
		observed["left"] = {"code": code, "reason": reason}
	)
	var active_snapshot := _started_snapshot("room-a", "human-a", 20)
	active_snapshot["turn_number"] = 1
	active_snapshot["played_cards"] = [
		_card("played-2", 2, "clubs", 0),
		_card("played-3", 3, "spades", 0),
		_card("played-4", 4, "hearts", 0),
	]
	active_snapshot["played_category"] = "straight"
	active_snapshot["played_score"] = 5
	active_snapshot["play_events"] = [{
		"turn_number": 1,
		"actor_seat_index": 0,
		"cards": active_snapshot["played_cards"].duplicate(true),
		"category": "straight",
		"score": 5,
	}]
	adapter.publish_game_room_state(active_snapshot)
	adapter.publish_match_private_state({
		"participant_id": "human-a",
		"hand": [_card("local-card", 11, "clubs", 0)],
	})

	adapter.publish_game_room_left(4000, "主动离开")

	_expect_equal(observed["left"], {"code": 4000, "reason": "主动离开"}, "离开事件")
	_expect_equal(match_store.room_id, "", "离开清空房间标识")
	_expect_equal(match_store.local_participant_id, "", "离开清空本地参与者")
	_expect_equal(match_store.status, "", "离开清空房间状态")
	_expect_equal(match_store.phase, "", "离开清空比赛阶段")
	_expect_equal(match_store.actor_seat_index, -1, "离开清空行动席位")
	_expect_equal(match_store.draw_pile_count, 0, "离开清空牌堆数量")
	_expect_equal(match_store.sealed_card_count, 0, "离开清空封存牌数量")
	_expect_equal(match_store.turn_number, 0, "离开清空回合编号")
	_expect_equal(match_store.get_played_cards(), [], "离开清空公开出牌")
	_expect_equal(match_store.get_play_events(), [], "离开清空出牌历史")
	_expect_equal(match_store.played_category, "", "离开清空牌型")
	_expect_equal(match_store.played_score, 0, "离开清空本轮得分")
	_expect_equal(match_store.get_participants(), [], "离开清空参与者")
	_expect_equal(match_store.get_contest_rounds(), [], "离开清空拼点历史")
	_expect_equal(match_store.get_local_hand(), [], "离开清空私有手牌")
	_expect_equal(observed["state_change_count"], 2, "离开通知公共清空")
	_expect_equal(observed["private_change_count"], 2, "离开通知私有清空")

	adapter.publish_game_room_state(_started_snapshot("room-b", "human-z", 18))
	_expect_equal(match_store.room_id, "room-b", "接收下一房间状态")
	_expect_equal(observed["activation_count"], 2, "下一房间可再次激活")


func _started_snapshot(room_id: String, local_participant_id: String, draw_pile_count: int) -> Dictionary:
	return {
		"room_id": room_id,
		"local_participant_id": local_participant_id,
		"status": "started",
		"phase": "actor_play",
		"actor_seat_index": 2,
		"draw_pile_count": draw_pile_count,
		"seats": [
			_seat(0, "human-a", "甲", false, true, 0, 8),
			_seat(1, "human-b", "乙", false, true, 2, 8),
			_seat(2, "bot-c", "机器人 3", true, true, 4, 8),
			_seat(3, "bot-d", "机器人 4", true, true, 1, 8),
		],
		"contest_rounds": [{
			"round_index": 0,
			"reveals": [{"seat_index": 2, "card": _card("one-hearts-a", 14, "hearts", 0)}],
		}],
	}


func _seat(
	seat_index: int,
	participant_id: String,
	nickname: String,
	is_bot: bool,
	is_ready: bool,
	score: int,
	hand_count: int
) -> Dictionary:
	return {
		"seat_index": seat_index,
		"participant_id": participant_id,
		"nickname": nickname,
		"is_bot": is_bot,
		"is_ready": is_ready,
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


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
