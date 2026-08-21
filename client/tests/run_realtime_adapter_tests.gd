extends SceneTree

const Adapter = preload("res://scripts/network/colyseus_realtime_adapter.gd")
const FakeColyseusClient = preload("res://tests/fakes/fake_colyseus_client.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_failed_join_is_disposed()
	_test_failed_retry_preserves_active_room()
	_test_new_attempt_detaches_old_pending_room()
	_test_null_retry_preserves_active_room()
	_test_play_cards_intention_is_sent_to_active_room()
	_test_claim_intentions_are_sent_to_active_room()
	_test_discard_intention_is_sent_to_active_room()
	_test_match_public_state_is_normalized_without_private_fields()
	_test_public_play_state_is_normalized_from_whitelisted_fields()
	_test_public_claim_reveal_is_normalized_from_whitelisted_fields()
	_test_public_discard_history_is_not_truncated_to_one_turn()
	_test_claim_event_history_is_normalized_from_whitelisted_fields()
	_test_public_discard_state_is_normalized_from_whitelisted_fields()
	_test_only_local_match_private_state_is_normalized()
	_test_local_claim_confirmation_is_normalized_privately()

	if _failures.is_empty():
		print("PASS: realtime adapter lifecycle tests")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_failed_join_is_disposed() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed_failures: Array[String] = []
	var joined_ids: Array[String] = []
	adapter.game_room_failed.connect(func(message: String): observed_failures.append(message))
	adapter.game_room_joined.connect(func(room_id: String): joined_ids.append(room_id))
	var stale_room := client.queue_join_room("locked-room")

	adapter.join_game_room("locked-room", "甲")
	stale_room.emit_error(421, "房间已锁定")

	_expect_equal(joined_ids, [], "失败加入不应通知 joined")
	_expect_equal(stale_room.leave_count, 1, "失败 wrapper 应被 leave")
	_expect_equal(stale_room.connection_count(&"error"), 0, "失败 wrapper 的回调应断开")
	_expect_equal(observed_failures, ["房间已锁定"], "失败加入错误应只通知一次")
	adapter.queue_free()


func _test_failed_retry_preserves_active_room() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed := {"state_count": 0, "leave_count": 0}
	adapter.game_room_state_changed.connect(func(_state: Dictionary): observed["state_count"] += 1)
	adapter.game_room_left.connect(func(_code: int, _reason: String): observed["leave_count"] += 1)

	var active_room := client.queue_join_room("active-room")
	adapter.join_game_room("active-room", "甲")
	active_room.emit_joined()
	var stale_room := client.queue_join_room("full-room")
	adapter.join_game_room("full-room", "甲")
	stale_room.emit_error(421, "房间已满")

	_expect_equal(stale_room.leave_count, 1, "失败重试 wrapper 应被 leave")
	_expect_equal(stale_room.connection_count(&"joined"), 0, "失败重试 wrapper 的回调应断开")
	adapter.set_ready(true)
	_expect_equal(
		active_room.sent_messages,
		[{"type": "set_ready", "data": {"ready": true}}],
		"失败重试后意图仍应路由到当前 active 房间"
	)
	active_room.emit_state({"status": "waiting"})
	stale_room.emit_state({"status": "started"})
	stale_room.emit_left(1000, "过期")
	_expect_equal(observed["state_count"], 1, "旧 wrapper 回调不应污染 active 状态")
	_expect_equal(observed["leave_count"], 0, "旧 wrapper 离开不应清理 active 房间")
	adapter.queue_free()


func _test_new_attempt_detaches_old_pending_room() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var joined_ids: Array[String] = []
	adapter.game_room_joined.connect(func(room_id: String): joined_ids.append(room_id))

	var first_pending := client.queue_join_room("first-pending")
	adapter.join_game_room("first-pending", "甲")
	var second_pending := client.queue_join_room("second-pending")
	adapter.join_game_room("second-pending", "甲")

	_expect_equal(first_pending.leave_count, 1, "新尝试应清理旧 pending wrapper")
	_expect_equal(first_pending.connection_count(&"joined"), 0, "旧 pending 回调应断开")
	first_pending.emit_joined()
	second_pending.emit_joined()
	_expect_equal(joined_ids, ["second-pending"], "只应通知新尝试的 joined")
	adapter.set_ready(true)
	_expect_equal(
		second_pending.sent_messages,
		[{"type": "set_ready", "data": {"ready": true}}],
		"新尝试成功后意图应路由到新 active 房间"
	)
	adapter.queue_free()


func _test_null_retry_preserves_active_room() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var failures: Array[String] = []
	adapter.game_room_failed.connect(func(message: String): failures.append(message))

	var active_room := client.queue_join_room("active-room")
	adapter.join_game_room("active-room", "甲")
	active_room.emit_joined()
	var pending_room := client.queue_join_room("pending-room")
	adapter.join_game_room("pending-room", "甲")
	client.queue_null_join()
	adapter.join_game_room("stale-room", "甲")

	_expect_equal(pending_room.leave_count, 1, "空请求结果应 leave 旧 pending wrapper")
	_expect_equal(pending_room.connection_count(&"joined"), 0, "空请求结果应断开旧 pending 回调")
	_expect_equal(failures, ["房间请求未能发出"], "空请求结果应返回明确失败")
	adapter.set_ready(true)
	_expect_equal(
		active_room.sent_messages,
		[{"type": "set_ready", "data": {"ready": true}}],
		"空请求结果不应覆盖当前 active 房间"
	)
	adapter.queue_free()


func _test_play_cards_intention_is_sent_to_active_room() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var room := client.queue_join_room("match-room")
	adapter.join_game_room("match-room", "甲")
	room.emit_joined()
	var selected_card_ids: Array[String] = ["card-c", "card-a", "card-b"]
	if not adapter.has_method("play_cards"):
		_failures.append("Adapter 应公开 play_cards 意图")
		adapter.queue_free()
		return

	adapter.play_cards(selected_card_ids)

	_expect_equal(room.sent_messages, [{
		"type": "play_cards",
		"data": {"cardIds": ["card-c", "card-a", "card-b"]},
	}], "出牌意图应发送物理牌标识")
	adapter.queue_free()


func _test_claim_intentions_are_sent_to_active_room() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var room := client.queue_join_room("match-room")
	adapter.join_game_room("match-room", "甲")
	room.emit_joined()
	if not adapter.has_method("claim_card"):
		_failures.append("Adapter 应公开 claim_card 意图")
		adapter.queue_free()
		return

	adapter.claim_card("played-hearts-a")
	adapter.claim_card(null)

	_expect_equal(room.sent_messages, [
		{"type": "claim", "data": {"cardId": "played-hearts-a"}},
		{"type": "claim", "data": {"cardId": null}},
	], "抢牌与不抢意图应保留实体牌标识或 null")
	adapter.queue_free()


func _test_discard_intention_is_sent_to_active_room() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var room := client.queue_join_room("match-room")
	adapter.join_game_room("match-room", "甲")
	room.emit_joined()
	if not adapter.has_method("discard_card"):
		_failures.append("Adapter 应公开 discard_card 意图")
		adapter.queue_free()
		return

	adapter.discard_card("original-clubs-2", 6)

	_expect_equal(room.sent_messages, [{
		"type": "discard",
		"data": {"cardId": "original-clubs-2", "turnNumber": 6},
	}], "弃牌意图应发送原手牌的物理牌标识")
	adapter.queue_free()


func _test_match_public_state_is_normalized_without_private_fields() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed := {"snapshot": {}}
	adapter.game_room_state_changed.connect(
		func(snapshot: Dictionary): observed["snapshot"] = snapshot
	)
	var room := client.queue_join_room("match-room")
	adapter.join_game_room("match-room", "甲")
	room.emit_joined()
	room.emit_state({
		"status": "started",
		"displayName": "公开开局",
		"deckMode": "one",
		"actionDeadlineSeconds": 30,
		"hostParticipantId": "session-a",
		"phase": "actor_play",
		"actorSeatIndex": 2,
		"firstActorSeatIndex": 2,
		"drawPileCount": 20,
		"hand": [{"id": "leaked-local"}],
		"hands": {"session-b": [{"id": "leaked-other"}]},
		"seats": [
			_raw_seat(0, "session-a", "甲", false, 0, 8),
			_raw_seat(1, "session-b", "乙", false, 0, 8),
			_raw_seat(2, "bot-c", "机器人 3", true, 0, 8),
			_raw_seat(3, "bot-d", "机器人 4", true, 0, 8),
		],
		"contestRounds": [{
			"roundIndex": 0,
			"reveals": [{
				"seatIndex": 2,
				"card": {
					"id": "copy-0:hearts:14",
					"rank": 14,
					"suit": "hearts",
					"copyIndex": 0,
				},
			}],
			"tiedSeatIndexes": [],
			"winnerSeatIndex": 2,
		}],
	})

	var snapshot: Dictionary = observed["snapshot"]
	_expect_equal(snapshot.get("phase"), "actor_play", "比赛阶段规范化")
	_expect_equal(snapshot.get("actor_seat_index"), 2, "行动席位规范化")
	_expect_equal(snapshot.get("first_actor_seat_index"), 2, "首位行动席位规范化")
	_expect_equal(snapshot.get("draw_pile_count"), 20, "牌堆数量规范化")
	_expect_equal(snapshot["seats"][2].get("score"), 0, "公开分数规范化")
	_expect_equal(snapshot["seats"][2].get("hand_count"), 8, "公开手牌数量规范化")
	_expect_equal(snapshot.get("contest_rounds"), [{
		"round_index": 0,
		"reveals": [{
			"seat_index": 2,
			"card": {
				"id": "copy-0:hearts:14",
				"rank": 14,
				"suit": "hearts",
				"copy_index": 0,
			},
		}],
		"tied_seat_indexes": [],
		"winner_seat_index": 2,
	}], "拼点历史规范化")
	_expect_equal(snapshot.has("hand"), false, "公开快照丢弃本地手牌")
	_expect_equal(snapshot.has("hands"), false, "公开快照丢弃其他手牌")
	adapter.queue_free()


func _test_public_play_state_is_normalized_from_whitelisted_fields() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed := {"snapshot": {}}
	adapter.game_room_state_changed.connect(
		func(snapshot: Dictionary): observed["snapshot"] = snapshot
	)
	var room := client.queue_join_room("play-room")
	adapter.join_game_room("play-room", "甲")
	room.emit_joined()
	room.emit_state({
		"status": "started",
		"phase": "claim_commit",
		"turnNumber": 3,
		"playedCards": [
			_raw_card("copy-0:hearts:12", 12, "hearts", 0, "drop-me"),
			_raw_card("copy-0:hearts:13", 13, "hearts", 0, "drop-me"),
			_raw_card("copy-0:hearts:14", 14, "hearts", 0, "drop-me"),
		],
		"playedCategory": "straight_flush",
		"playedScore": 10,
		"playEvents": [{
			"turnNumber": 3,
			"actorSeatIndex": 2,
			"cards": [
				_raw_card("copy-0:hearts:12", 12, "hearts", 0, "drop-me"),
				_raw_card("copy-0:hearts:13", 13, "hearts", 0, "drop-me"),
				_raw_card("copy-0:hearts:14", 14, "hearts", 0, "drop-me"),
			],
			"category": "straight_flush",
			"score": 10,
			"unrevealedClaim": "drop-me",
		}],
		"claimCommits": {"session-b": "copy-0:hearts:12"},
	})

	var snapshot: Dictionary = observed["snapshot"]
	_expect_equal(snapshot.get("turn_number"), 3, "回合编号规范化")
	_expect_equal(snapshot.get("played_cards"), [
		_card("copy-0:hearts:12", 12, "hearts", 0),
		_card("copy-0:hearts:13", 13, "hearts", 0),
		_card("copy-0:hearts:14", 14, "hearts", 0),
	], "公开出牌只保留牌面白名单")
	_expect_equal(snapshot.get("played_category"), "straight_flush", "公开牌型规范化")
	_expect_equal(snapshot.get("played_score"), 10, "公开出牌得分规范化")
	_expect_equal(snapshot.get("play_events"), [{
		"turn_number": 3,
		"actor_seat_index": 2,
		"cards": [
			_card("copy-0:hearts:12", 12, "hearts", 0),
			_card("copy-0:hearts:13", 13, "hearts", 0),
			_card("copy-0:hearts:14", 14, "hearts", 0),
		],
		"category": "straight_flush",
		"score": 10,
	}], "公开出牌事件只保留可审计白名单")
	_expect_equal(snapshot.has("claimCommits"), false, "公开快照不透传抢牌秘密")
	adapter.queue_free()


func _test_only_local_match_private_state_is_normalized() -> void:
	var adapter := _new_adapter()
	if not adapter.has_signal("match_private_state_changed"):
		_failures.append("Adapter 应公开比赛私有状态信号")
		adapter.queue_free()
		return
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed: Array[Dictionary] = []
	adapter.match_private_state_changed.connect(
		func(snapshot: Dictionary): observed.append(snapshot)
	)
	var room := client.queue_join_room("private-room")
	adapter.join_game_room("private-room", "甲")
	room.emit_joined()
	room.message_received.emit("match_private_state", {
		"participantId": "session-a",
		"seatIndex": 0,
		"hand": [{
			"id": "copy-0:clubs:2",
			"rank": 2,
			"suit": "clubs",
			"copyIndex": 0,
			"transportOnly": "drop-me",
		}],
		"anotherHand": [{"id": "drop-me"}],
	})
	room.message_received.emit("match_private_state", {
		"participantId": "session-b",
		"seatIndex": 1,
		"hand": [{
			"id": "copy-0:hearts:14",
			"rank": 14,
			"suit": "hearts",
			"copyIndex": 0,
		}],
	})

	_expect_equal(observed, [{
		"participant_id": "session-a",
		"seat_index": 0,
		"hand": [{
			"id": "copy-0:clubs:2",
			"rank": 2,
			"suit": "clubs",
			"copy_index": 0,
		}],
		"claim_committed": false,
		"claim_card_id": null,
	}], "仅规范化本地参与者私有手牌")
	adapter.queue_free()


func _test_local_claim_confirmation_is_normalized_privately() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed: Array[Dictionary] = []
	adapter.match_private_state_changed.connect(
		func(snapshot: Dictionary): observed.append(snapshot)
	)
	var room := client.queue_join_room("private-room")
	adapter.join_game_room("private-room", "甲")
	room.emit_joined()
	room.message_received.emit("match_private_state", {
		"participantId": "session-a",
		"seatIndex": 0,
		"hand": [],
		"claimCommitted": true,
		"claimCardId": "copy-0:hearts:14",
		"otherClaim": "must-not-pass",
	})
	room.message_received.emit("match_private_state", {
		"participantId": "session-b",
		"seatIndex": 1,
		"hand": [],
		"claimCommitted": true,
		"claimCardId": "copy-0:spades:13",
	})

	_expect_equal(observed, [{
		"participant_id": "session-a",
		"seat_index": 0,
		"hand": [],
		"claim_committed": true,
		"claim_card_id": "copy-0:hearts:14",
	}], "只规范化本地抢牌确认且不泄露额外字段")
	adapter.queue_free()


func _test_public_claim_reveal_is_normalized_from_whitelisted_fields() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed := {"snapshot": {}}
	adapter.game_room_state_changed.connect(
		func(snapshot: Dictionary): observed["snapshot"] = snapshot
	)
	var room := client.queue_join_room("claim-room")
	adapter.join_game_room("claim-room", "甲")
	room.emit_joined()
	var collision_card := _raw_card("played-queen", 12, "hearts", 0)
	var unique_card := _raw_card("played-ace", 14, "hearts", 0)
	var discarded_card := _raw_card("played-king", 13, "hearts", 0)
	room.emit_state({
		"status": "started",
		"phase": "claim_reveal",
		"claimCommitCount": 3,
		"revealedClaims": [
			{"seatIndex": 3, "passed": true, "cardId": "", "privateChoice": "drop-me"},
			{"seatIndex": 1, "passed": false, "cardId": "played-ace"},
			{"seatIndex": 2, "passed": false, "cardId": "played-queen"},
			{"seatIndex": 2, "passed": false, "cardId": "played-queen"},
		],
		"claimAwards": [
			{"seatIndex": 2, "card": collision_card, "source": "collision"},
			{"seatIndex": 1, "card": unique_card, "source": "unique"},
			{"seatIndex": 1, "card": unique_card, "source": "unique"},
		],
		"discardedCards": [discarded_card, discarded_card],
		"claimChoices": {"must": "not pass"},
	})

	var snapshot: Dictionary = observed["snapshot"]
	_expect_equal(snapshot.has("claim_commit_count"), false, "公开快照忽略抢牌提交计数")
	_expect_equal(snapshot.get("revealed_claims"), [
		{"seat_index": 1, "card_id": "played-ace"},
		{"seat_index": 2, "card_id": "played-queen"},
		{"seat_index": 3, "card_id": null},
	], "同时揭晓选择按席位规范化并去重")
	_expect_equal(snapshot.get("claim_awards"), [
		{"seat_index": 1, "card": _card("played-ace", 14, "hearts", 0), "source": "unique"},
		{"seat_index": 2, "card": _card("played-queen", 12, "hearts", 0), "source": "collision"},
	], "公开抢牌结果按席位规范化并去重")
	_expect_equal(snapshot.get("discarded_cards"), [
		_card("played-king", 13, "hearts", 0),
	], "公共弃牌按实体牌去重")
	_expect_equal(snapshot.has("claim_choices"), false, "未揭晓选择不进入应用快照")
	adapter.queue_free()


func _test_public_discard_history_is_not_truncated_to_one_turn() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed := {"snapshot": {}}
	adapter.game_room_state_changed.connect(
		func(snapshot: Dictionary): observed["snapshot"] = snapshot
	)
	var room := client.queue_join_room("discard-history-room")
	adapter.join_game_room("discard-history-room", "甲")
	room.emit_joined()
	room.emit_state({
		"status": "started",
		"discardedCards": [
			_raw_card("discard-2", 2, "clubs", 0),
			_raw_card("discard-3", 3, "spades", 0),
			_raw_card("discard-4", 4, "diamonds", 0),
			_raw_card("discard-5", 5, "hearts", 0),
			_raw_card("discard-6", 6, "clubs", 0),
		],
	})

	_expect_equal(observed["snapshot"].get("discarded_cards"), [
		_card("discard-2", 2, "clubs", 0),
		_card("discard-3", 3, "spades", 0),
		_card("discard-4", 4, "diamonds", 0),
		_card("discard-5", 5, "hearts", 0),
		_card("discard-6", 6, "clubs", 0),
	], "公共弃牌历史保留多个回合")
	adapter.queue_free()


func _test_claim_event_history_is_normalized_from_whitelisted_fields() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed := {"snapshot": {}}
	adapter.game_room_state_changed.connect(
		func(snapshot: Dictionary): observed["snapshot"] = snapshot
	)
	var room := client.queue_join_room("claim-history-room")
	adapter.join_game_room("claim-history-room", "甲")
	room.emit_joined()
	room.emit_state({
		"status": "started",
		"claimEvents": [{
			"turnNumber": 2,
			"claims": [
				{"seatIndex": 3, "passed": true, "cardId": ""},
				{"seatIndex": 1, "passed": false, "cardId": "played-ace"},
				{"seatIndex": 2, "passed": false, "cardId": "played-queen"},
			],
			"awards": [
				{"seatIndex": 2, "card": _raw_card("collision-king", 13, "hearts", 0), "source": "collision"},
				{"seatIndex": 1, "card": _raw_card("played-ace", 14, "hearts", 0), "source": "unique"},
			],
			"discardedCards": [_raw_card("discarded-queen", 12, "hearts", 0)],
			"privateChoices": "drop-me",
		}],
	})

	_expect_equal(observed["snapshot"].get("claim_events"), [{
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
	}], "抢牌结果历史按回合规范化且只保留公开字段")
	adapter.queue_free()


func _test_public_discard_state_is_normalized_from_whitelisted_fields() -> void:
	var adapter := _new_adapter()
	var client := FakeColyseusClient.new()
	adapter._client = client
	var observed := {"snapshot": {}}
	adapter.game_room_state_changed.connect(
		func(snapshot: Dictionary): observed["snapshot"] = snapshot
	)
	var room := client.queue_join_room("discard-room")
	adapter.join_game_room("discard-room", "甲")
	room.emit_joined()
	var discarded_two := _raw_card("original-clubs-2", 2, "clubs", 0, "drop-me")
	var discarded_three := _raw_card("original-spades-3", 3, "spades", 0, "drop-me")
	room.emit_state({
		"status": "started",
		"phase": "award_discard",
		"pendingDiscardSeatIndexes": [3, 1, 3, 9],
		"sealedCards": [discarded_two, discarded_three, discarded_two],
		"discardEvents": [
			{"turnNumber": 2, "seatIndex": 3, "card": discarded_three, "private": "drop-me"},
			{"turnNumber": 2, "seatIndex": 1, "card": discarded_two},
			{"turnNumber": 2, "seatIndex": 1, "card": discarded_two},
			{"turnNumber": 0, "seatIndex": 0, "card": discarded_two},
			{"turnNumber": 2, "seatIndex": 8, "card": discarded_two},
		],
	})

	var snapshot: Dictionary = observed["snapshot"]
	_expect_equal(snapshot.get("phase"), "award_discard", "弃牌阶段规范化")
	_expect_equal(snapshot.get("pending_discard_seat_indexes"), [1, 3], "待弃牌席位规范化并去重")
	_expect_equal(snapshot.get("sealed_cards"), [
		_card("original-clubs-2", 2, "clubs", 0),
		_card("original-spades-3", 3, "spades", 0),
	], "封存牌按实体标识去重")
	_expect_equal(snapshot.get("discard_events"), [
		{
			"turn_number": 2,
			"seat_index": 1,
			"card": _card("original-clubs-2", 2, "clubs", 0),
		},
		{
			"turn_number": 2,
			"seat_index": 3,
			"card": _card("original-spades-3", 3, "spades", 0),
		},
	], "弃牌事件按回合和席位规范化且只保留公开字段")
	adapter.queue_free()


func _raw_seat(
	seat_index: int,
	participant_id: String,
	nickname: String,
	is_bot: bool,
	score: int,
	hand_count: int
) -> Dictionary:
	return {
		"seatIndex": seat_index,
		"participantId": participant_id,
		"nickname": nickname,
		"bot": is_bot,
		"ready": true,
		"score": score,
		"handCount": hand_count,
		"hand": [{"id": "must-not-pass"}],
	}


func _raw_card(
	card_id: String,
	rank: int,
	suit: String,
	copy_index: int,
	transport_only: String = ""
) -> Dictionary:
	return {
		"id": card_id,
		"rank": rank,
		"suit": suit,
		"copyIndex": copy_index,
		"transportOnly": transport_only,
	}


func _card(card_id: String, rank: int, suit: String, copy_index: int) -> Dictionary:
	return {
		"id": card_id,
		"rank": rank,
		"suit": suit,
		"copy_index": copy_index,
	}


func _new_adapter() -> Adapter:
	var adapter := Adapter.new()
	root.add_child(adapter)
	adapter._connected = true
	return adapter


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
