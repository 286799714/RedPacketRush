extends SceneTree

const AppShell = preload("res://scripts/app/app_shell.gd")
const FakeRealtimeAdapter = preload("res://tests/fakes/fake_realtime_adapter.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var adapter := FakeRealtimeAdapter.new()
	var shell := AppShell.new()
	shell.set_realtime_adapter(adapter)
	root.add_child(shell)
	await process_frame
	_expect_equal(shell.get_current_surface(), "lobby", "初始大厅")

	adapter.publish_game_room_joined("room-a")
	await process_frame
	_expect_equal(shell.get_current_surface(), "room", "进入房间")
	adapter.publish_game_room_state({
		"room_id": "room-a",
		"local_participant_id": "human-a",
		"status": "waiting",
		"phase": "",
		"actor_seat_index": -1,
		"draw_pile_count": 0,
		"seats": _seats(),
		"contest_rounds": [],
	})
	adapter.start_match()
	await process_frame
	_expect_equal(shell.get_current_surface(), "room", "开始意图不提前切换")

	adapter.publish_game_room_state({
		"room_id": "room-a",
		"local_participant_id": "human-a",
		"status": "started",
		"phase": "actor_play",
		"actor_seat_index": 0,
		"draw_pile_count": 20,
		"seats": _seats(),
		"contest_rounds": [],
	})
	await process_frame
	_expect_equal(shell.get_current_surface(), "match", "权威开局状态进入牌桌")

	adapter.publish_game_room_left(1000, "")
	await process_frame
	_expect_equal(shell.get_current_surface(), "lobby", "离开返回大厅")

	shell.queue_free()
	await process_frame
	if _failures.is_empty():
		print("PASS: app shell tests")
		quit(0)
		return
	for failure in _failures:
		push_error(failure)
	quit(1)


func _seats() -> Array[Dictionary]:
	return [
		_seat(0, "human-a", "甲", false),
		_seat(1, "bot-b", "机器人 2", true),
		_seat(2, "bot-c", "机器人 3", true),
		_seat(3, "bot-d", "机器人 4", true),
	]


func _seat(
	seat_index: int,
	participant_id: String,
	nickname: String,
	is_bot: bool
) -> Dictionary:
	return {
		"seat_index": seat_index,
		"participant_id": participant_id,
		"nickname": nickname,
		"is_bot": is_bot,
		"is_ready": true,
		"score": 0,
		"hand_count": 8,
	}


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
