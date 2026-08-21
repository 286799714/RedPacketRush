extends SceneTree

const MatchScreen = preload("res://scripts/match/match_screen.gd")
const LobbyScreen = preload("res://scripts/lobby/lobby_screen.gd")
const RoomScreen = preload("res://scripts/room/room_screen.gd")
const LobbyStore = preload("res://scripts/lobby/lobby_store.gd")
const RoomStore = preload("res://scripts/room/room_store.gd")
const FakeRealtimeAdapter = preload("res://tests/fakes/fake_realtime_adapter.gd")


class VisualMatchStore extends RefCounted:
	signal state_changed()
	signal private_state_changed()
	signal action_failed(code: String, message: String)

	var action_id := 1
	var private_action_id := 1
	var action_deadline_at_unix_ms := 0.0
	var connection_state := "connected"
	var phase := "actor_play"
	var actor_seat_index := 0
	var draw_pile_count := 17
	var sealed_card_count := 0
	var room_id := "visual-room"
	var local_participant_id := "human-a"
	var deck_mode := "one"
	var turn_number := 1
	var played_category := ""
	var played_score := 0
	var claim_committed := false
	var claim_card_id: Variant = null
	var final_committed := false
	var participants: Array[Dictionary] = []
	var contest_rounds: Array[Dictionary] = []
	var played_cards: Array[Dictionary] = []
	var play_events: Array[Dictionary] = []
	var claim_events: Array[Dictionary] = []
	var discard_events: Array[Dictionary] = []
	var pending_discard_seat_indexes: Array[int] = []
	var final_results: Array[Dictionary] = []
	var winner_seat_indexes: Array[int] = []
	var final_events: Array[Dictionary] = []
	var local_hand: Array[Dictionary] = []
	var final_groups: Array = []

	func get_participants() -> Array[Dictionary]:
		return participants

	func get_contest_rounds() -> Array[Dictionary]:
		return contest_rounds

	func get_played_cards() -> Array[Dictionary]:
		return played_cards

	func get_play_events() -> Array[Dictionary]:
		return play_events

	func get_claim_events() -> Array[Dictionary]:
		return claim_events

	func get_final_results() -> Array[Dictionary]:
		return final_results

	func get_winner_seat_indexes() -> Array[int]:
		return winner_seat_indexes

	func get_final_events() -> Array[Dictionary]:
		return final_events

	func get_discard_events() -> Array[Dictionary]:
		return discard_events

	func get_pending_discard_seat_indexes() -> Array[int]:
		return pending_discard_seat_indexes

	func get_local_hand() -> Array[Dictionary]:
		return local_hand

	func get_final_groups() -> Array:
		return final_groups

	func is_action_context_ready() -> bool:
		return connection_state == "connected" and action_id == private_action_id

	func play_cards(_card_ids: Array[String]) -> void:
		pass

	func claim_card(_card_id: Variant) -> void:
		pass

	func submit_final_selection(_groups: Array) -> void:
		pass

	func submit_best_final_selection() -> void:
		pass


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var output_directory := _read_output_directory()
	var error := DirAccess.make_dir_recursive_absolute(output_directory)
	if error != OK:
		push_error("could not create screenshot directory: %s" % error_string(error))
		quit(1)
		return
	if not await _capture_lobby_room_states(output_directory):
		quit(1)
		return

	for viewport_size in [Vector2i(960, 540), Vector2i(1280, 720)]:
		if not await _capture_state("actor_play", viewport_size, output_directory, "actor-play-two-deck"):
			quit(1)
			return
		if not await _capture_state("claim_commit", viewport_size, output_directory, "claim-commit-selected"):
			quit(1)
			return
		if not await _capture_state("claim_reveal", viewport_size, output_directory, "claim-reveal-collision"):
			quit(1)
			return
		for spec in [
			{"phase": "award_discard", "label": "award-discard-protected"},
			{"phase": "actor_play", "label": "match-reconnecting"},
			{"phase": "actor_play", "label": "match-validation-error"},
			{"phase": "final_commit", "label": "final-commit"},
			{"phase": "final_reveal", "label": "final-reveal"},
			{"phase": "finished", "label": "finished"},
		]:
			if not await _capture_state(spec["phase"], viewport_size, output_directory, spec["label"]):
				quit(1)
				return

	print("PASS: captured nonblank match screen states in %s" % output_directory)
	quit(0)


func _capture_lobby_room_states(output_directory: String) -> bool:
	var lobby_labels := [
		"lobby-loading-empty",
		"lobby-empty",
		"lobby-validation-error",
		"lobby-retry",
		"lobby-populated-selected",
	]
	for viewport_size in [Vector2i(960, 540), Vector2i(1280, 720)]:
		for label in lobby_labels:
			if not await _capture_lobby_state(label, viewport_size, output_directory):
				return false
		if not await _capture_room_state("room-full-host", viewport_size, output_directory):
			return false
	return true


func _capture_lobby_state(
	label: String,
	viewport_size: Vector2i,
	output_directory: String
) -> bool:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var adapter := FakeRealtimeAdapter.new()
	var screen := LobbyScreen.new()
	screen.set_realtime_adapter(adapter)
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(viewport_size)
	viewport.add_child(screen)
	await process_frame
	await process_frame
	match label:
		"lobby-loading-empty":
			adapter.publish_connection_state("connecting")
		"lobby-empty":
			adapter.publish_connection_state("connected")
			adapter.publish_rooms([])
		"lobby-validation-error":
			adapter.publish_connection_state("connected")
			screen._nickname_input.text = "甲"
			screen._endpoint_input.text = "http://invalid"
			screen._connect_button.pressed.emit()
		"lobby-retry":
			adapter.publish_connection_state("retryable_error", "服务器暂时不可用")
		"lobby-populated-selected":
			adapter.publish_connection_state("connected")
			screen._nickname_input.text = "甲"
			adapter.publish_rooms([
				{"room_id": "room-a", "name": "午休局", "participant_count": 3, "seat_capacity": 4, "deck_mode": "one", "action_deadline_seconds": 30},
				{"room_id": "room-b", "name": "双牌局", "participant_count": 1, "seat_capacity": 4, "deck_mode": "two", "action_deadline_seconds": 60},
			])
			await process_frame
			var root_item := screen._room_tree.get_root()
			var first_item := root_item.get_first_child() if root_item != null else null
			if first_item != null:
				screen._room_tree.set_selected(first_item, 0)
				screen._on_room_selected()
	await process_frame
	await process_frame
	return await _save_capture(viewport, output_directory, label, viewport_size)


func _capture_room_state(
	label: String,
	viewport_size: Vector2i,
	output_directory: String
) -> bool:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	var adapter := FakeRealtimeAdapter.new()
	var store := RoomStore.new(adapter)
	var screen := RoomScreen.new()
	screen.set_room_store(store)
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(viewport_size)
	viewport.add_child(screen)
	await process_frame
	adapter.publish_game_room_state({
		"room_id": "room-full",
		"local_participant_id": "human-a",
		"status": "waiting",
		"display_name": "双副牌 · 满员等待",
		"deck_mode": "two",
		"action_deadline_seconds": 30,
		"host_participant_id": "human-a",
		"seats": [
			_seat(0, "human-a", "甲", false, 0, 8),
			_seat(1, "human-b", "乙", false, 0, 8),
			_seat(2, "bot-c", "机器人丙", true, 0, 8),
			_seat(3, "bot-d", "机器人丁", true, 0, 8),
		],
	})
	await process_frame
	await process_frame
	return await _save_capture(viewport, output_directory, label, viewport_size)


func _save_capture(
	viewport: SubViewport,
	output_directory: String,
	label: String,
	viewport_size: Vector2i
) -> bool:
	for frame in range(2):
		await process_frame
	var texture: Texture2D = viewport.get_texture()
	if texture == null:
		push_error("capture has no viewport texture: %s" % label)
		viewport.queue_free()
		await process_frame
		return false
	var image: Image = texture.get_image()
	if image == null:
		push_error("capture texture has no image: %s" % label)
		viewport.queue_free()
		await process_frame
		return false
	var output_path := output_directory.path_join("%s-%dx%d.png" % [label, viewport_size.x, viewport_size.y])
	var save_error := image.save_png(output_path)
	var nonblank := _has_pixel_variation(image)
	viewport.queue_free()
	await process_frame
	if save_error != OK:
		push_error("could not save %s: %s" % [output_path, error_string(save_error)])
		return false
	if not nonblank:
		push_error("captured image is blank: %s" % output_path)
		return false
	return true


func _capture_state(
	phase: String,
	viewport_size: Vector2i,
	output_directory: String,
	visual_state: String = ""
) -> bool:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var store := _make_store(phase, visual_state)
	var screen := MatchScreen.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(viewport_size)
	screen.set_match_store(store)
	viewport.add_child(screen)
	await process_frame
	await process_frame
	if visual_state == "match-validation-error":
		screen._on_action_failed("invalid_play", "出牌失败：请选择三张不同的手牌")
		await process_frame

	if phase == "actor_play":
		for index in range(3):
			var card_button := screen.find_child("HandCard%d" % index, true, false) as Button
			if card_button == null:
				push_error("actor-play capture could not find hand card %d" % index)
				viewport.queue_free()
				await process_frame
				return false
			card_button.button_pressed = true
		await process_frame
	elif phase == "claim_commit":
		var claim_card := screen.find_child("ClaimCard1", true, false) as Button
		if claim_card == null:
			push_error("claim-commit capture could not find a selectable played card")
			viewport.queue_free()
			await process_frame
			return false
		claim_card.button_pressed = true
		await process_frame
	elif phase == "claim_reveal":
		await create_timer(0.25).timeout
	elif phase == "award_discard":
		await process_frame
	elif phase == "final_commit":
		for rank in [2, 3, 4]:
			var card_button := _find_button_with_content(screen, "%d♣" % rank)
			if card_button == null:
				push_error("final-commit capture could not find A-group card %d" % rank)
				return false
			card_button.button_pressed = true
			await process_frame
		var group_b_button := _find_button(screen, "B 组")
		if group_b_button == null:
			push_error("final-commit capture could not find B-group mode")
			return false
		group_b_button.button_pressed = true
		for rank in [5, 6, 7]:
			var card_button := _find_button_with_content(screen, "%d♠" % rank)
			if card_button == null:
				push_error("final-commit capture could not find B-group card %d" % rank)
				return false
			card_button.button_pressed = true
			await process_frame

	for frame in range(3):
		await process_frame
	var image := viewport.get_texture().get_image()
	var filename_stem := visual_state if not visual_state.is_empty() else phase
	var filename := "%s-%dx%d.png" % [filename_stem, viewport_size.x, viewport_size.y]
	var output_path := output_directory.path_join(filename)
	var save_error := image.save_png(output_path)
	var nonblank := _has_pixel_variation(image)
	viewport.queue_free()
	await process_frame
	if save_error != OK:
		push_error("could not save %s: %s" % [output_path, error_string(save_error)])
		return false
	if not nonblank:
		push_error("captured image is blank: %s" % output_path)
		return false
	return true


func _make_store(phase: String, visual_state: String = "") -> VisualMatchStore:
	var store := VisualMatchStore.new()
	store.phase = phase
	store.participants = [
		_seat(0, "human-a", "甲", false, 10, 8),
		_seat(1, "human-b", "乙", false, 4, 8),
		_seat(2, "bot-c", "机器人丙", true, 2, 8),
		_seat(3, "bot-d", "机器人丁", true, 1, 8),
	]
	store.contest_rounds = [{
		"round_index": 0,
		"reveals": [
			{"seat_index": 0, "card": _card("contest-a", 14, "hearts", 0)},
			{"seat_index": 1, "card": _card("contest-b", 13, "spades", 0)},
			{"seat_index": 2, "card": _card("contest-c", 9, "diamonds", 0)},
			{"seat_index": 3, "card": _card("contest-d", 7, "clubs", 0)},
		],
		"tied_seat_indexes": [],
		"winner_seat_index": 0,
	}]
	store.local_hand = [
		_card("local-2", 2, "clubs", 0),
		_card("local-5", 5, "spades", 0),
		_card("local-8", 8, "diamonds", 0),
		_card("local-10", 10, "hearts", 0),
		_card("local-j", 11, "clubs", 0),
		_card("local-q", 12, "diamonds", 0),
		_card("local-k", 13, "spades", 0),
		_card("local-a", 14, "hearts", 0),
	]
	if phase in ["claim_commit", "claim_reveal"]:
		store.actor_seat_index = 1
		store.turn_number = 2
		store.played_cards = [
			_card("played-q", 12, "hearts", 0),
			_card("played-k", 13, "hearts", 0),
			_card("played-a", 14, "hearts", 0),
		]
		store.played_category = "straight_flush"
		store.played_score = 10
		store.play_events = [{
			"turn_number": 2,
			"actor_seat_index": 1,
			"cards": store.played_cards.duplicate(true),
			"category": "straight_flush",
			"score": 10,
		}]
	if phase == "claim_reveal":
		var queen: Dictionary = store.played_cards[0]
		var king: Dictionary = store.played_cards[1]
		var ace: Dictionary = store.played_cards[2]
		store.claim_committed = true
		store.claim_card_id = "played-a"
		var revealed_claims: Array[Dictionary] = [
			{"seat_index": 0, "card_id": "played-a"},
			{"seat_index": 2, "card_id": "played-q"},
			{"seat_index": 3, "card_id": "played-q"},
		]
		var claim_awards: Array[Dictionary] = [
			{"seat_index": 0, "card": ace, "source": "unique"},
			{"seat_index": 2, "card": king, "source": "collision"},
			{"seat_index": 3, "card": queen, "source": "collision"},
		]
		store.claim_events = [
			{
				"turn_number": 1,
				"claims": [
					{"seat_index": 0, "card_id": null},
					{"seat_index": 2, "card_id": null},
					{"seat_index": 3, "card_id": null},
				],
				"awards": [],
				"discarded_cards": [queen, king, ace],
			},
			{
				"turn_number": 2,
				"claims": revealed_claims.duplicate(true),
				"awards": claim_awards.duplicate(true),
				"discarded_cards": [],
			},
		]
		store.played_cards = []
	if phase in ["final_commit", "final_reveal", "finished"]:
		store.actor_seat_index = -1
		store.draw_pile_count = 0
		store.sealed_card_count = 2
		store.local_hand = _final_hand()
	if phase in ["final_reveal", "finished"]:
		store.final_committed = true
		store.final_groups = [
			["final-clubs-2", "final-clubs-3", "final-clubs-4"],
			["final-spades-5", "final-spades-6", "final-spades-7"],
		]
		store.participants = [
			_seat(0, "human-a", "甲", false, 22, 8),
			_seat(1, "human-b", "乙", false, 25, 8),
			_seat(2, "bot-c", "机器人丙", true, 25, 8),
			_seat(3, "bot-d", "机器人丁", true, 10, 8),
		]
		store.final_results = _final_results()
		store.winner_seat_indexes = [1, 2]
		store.final_events = [{
			"type": "final_settlement",
			"results": store.final_results,
			"winner_seat_indexes": store.winner_seat_indexes,
		}]
	match visual_state:
		"actor-play-two-deck":
			store.deck_mode = "two"
		"match-reconnecting":
			store.connection_state = "reconnecting"
		"match-validation-error":
			store.connection_state = "connected"
		"award-discard-protected":
			var awarded_card := _card("award-hearts-a-copy-1", 14, "hearts", 1)
			store.local_hand = [
				_card("original-clubs-2", 2, "clubs", 0),
				_card("original-spades-3", 3, "spades", 0),
				awarded_card,
				_card("original-diamonds-4", 4, "diamonds", 0),
				_card("original-hearts-5", 5, "hearts", 0),
				_card("original-clubs-6", 6, "clubs", 0),
				_card("original-spades-7", 7, "spades", 0),
				_card("original-diamonds-8", 8, "diamonds", 0),
				_card("original-hearts-9", 9, "hearts", 0),
			]
			store.deck_mode = "two"
			store.turn_number = 6
			store.pending_discard_seat_indexes = [0]
			store.claim_events = [{
				"turn_number": 6,
				"claims": [
					{"seat_index": 0, "card_id": awarded_card["id"]},
					{"seat_index": 2, "card_id": null},
					{"seat_index": 3, "card_id": null},
				],
				"awards": [{"seat_index": 0, "card": awarded_card, "source": "unique"}],
				"discarded_cards": [],
			}]
		"disconnected_human":
			var disconnected_seat := store.participants[1].duplicate(true)
			disconnected_seat["is_connected"] = false
			store.participants[1] = disconnected_seat
		"bot_takeover":
			var takeover_seat := store.participants[1].duplicate(true)
			takeover_seat["is_connected"] = false
			takeover_seat["is_bot"] = true
			store.participants[1] = takeover_seat
		"reconnecting":
			store.connection_state = "reconnecting"
	return store


func _read_output_directory() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			return argument.trim_prefix("--output-dir=")
	return ProjectSettings.globalize_path("res://../.scratch/ticket09-visuals/match")


func _has_pixel_variation(image: Image) -> bool:
	var sampled_colors: Dictionary = {}
	for y in range(0, image.get_height(), 24):
		for x in range(0, image.get_width(), 24):
			sampled_colors[image.get_pixel(x, y).to_html()] = true
			if sampled_colors.size() >= 4:
				return true
	return false


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
		"is_connected": true,
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


func _final_hand() -> Array[Dictionary]:
	return [
		_card("final-clubs-2", 2, "clubs", 0),
		_card("final-clubs-3", 3, "clubs", 0),
		_card("final-clubs-4", 4, "clubs", 0),
		_card("final-spades-5", 5, "spades", 0),
		_card("final-spades-6", 6, "spades", 0),
		_card("final-spades-7", 7, "spades", 0),
		_card("final-diamonds-10", 10, "diamonds", 0),
		_card("final-hearts-a", 14, "hearts", 0),
	]


func _final_results() -> Array[Dictionary]:
	return [
		_final_result(0, 12, "straight_flush", 10, "pair", 2, "seat0"),
		_final_result(1, 9, "straight", 5, "flush", 4, "seat1"),
		_final_result(2, 10, "three_of_a_kind", 8, "pair", 2, "seat2"),
		_final_result(3, 4, "high_card", 0, "flush", 4, "seat3"),
	]


func _final_result(
	seat_index: int,
	total_score: int,
	category_a: String,
	score_a: int,
	category_b: String,
	score_b: int,
	id_prefix: String
) -> Dictionary:
	return {
		"seat_index": seat_index,
		"groups": [
			{
				"cards": [
					_card("%s-a1" % id_prefix, 12, "hearts", 0),
					_card("%s-a2" % id_prefix, 13, "hearts", 0),
					_card("%s-a3" % id_prefix, 14, "hearts", 0),
				],
				"category": category_a,
				"score": score_a,
			},
			{
				"cards": [
					_card("%s-b1" % id_prefix, 2, "clubs", 0),
					_card("%s-b2" % id_prefix, 2, "spades", 0),
					_card("%s-b3" % id_prefix, 7, "diamonds", 0),
				],
				"category": category_b,
				"score": score_b,
			},
		],
		"total_score": total_score,
	}


func _find_button(root_node: Node, expected_text: String) -> Button:
	for node in root_node.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and node.text == expected_text:
			return node
	return null


func _find_button_with_content(root_node: Node, fragment: String) -> Button:
	for node in root_node.find_children("*", "Button", true, false):
		if node is Button and node.is_visible_in_tree() and _node_text(node).contains(fragment):
			return node
	return null


func _node_text(node: Node) -> String:
	var value := ""
	if node is Label:
		value += (node as Label).text
	for child in node.get_children():
		value += _node_text(child)
	return value
