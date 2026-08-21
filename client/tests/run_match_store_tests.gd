extends SceneTree

const FakeRealtimeAdapter = preload("res://tests/fakes/fake_realtime_adapter.gd")
const MatchStore = preload("res://scripts/match/match_store.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_started_snapshot_activates_match_once()
	_test_public_collections_are_sanitized_deep_copies()
	_test_only_targeted_private_hand_is_retained()
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
	adapter.publish_game_room_state(_started_snapshot("room-a", "human-a", 20))
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
