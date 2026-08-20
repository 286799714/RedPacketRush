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


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
