extends SceneTree

const MatchScreen = preload("res://scripts/match/match_screen.gd")


class VisualMatchStore extends RefCounted:
	signal state_changed()
	signal private_state_changed()
	signal action_failed(code: String, message: String)

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

	func get_local_hand() -> Array[Dictionary]:
		return local_hand

	func get_final_groups() -> Array:
		return final_groups

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

	for viewport_size in [Vector2i(960, 540), Vector2i(1280, 720)]:
		if not await _capture_state("actor_play", viewport_size, output_directory):
			quit(1)
			return
		if not await _capture_state("claim_commit", viewport_size, output_directory):
			quit(1)
			return
		if not await _capture_state("claim_reveal", viewport_size, output_directory):
			quit(1)
			return
		for final_phase in ["final_commit", "final_reveal", "finished"]:
			if not await _capture_state(final_phase, viewport_size, output_directory):
				quit(1)
				return

	print("PASS: captured nonblank match screen states in %s" % output_directory)
	quit(0)


func _capture_state(
	phase: String,
	viewport_size: Vector2i,
	output_directory: String
) -> bool:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)

	var store := _make_store(phase)
	var screen := MatchScreen.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(viewport_size)
	screen.set_match_store(store)
	viewport.add_child(screen)
	await process_frame
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
	var filename := "%s-%dx%d.png" % [phase, viewport_size.x, viewport_size.y]
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


func _make_store(phase: String) -> VisualMatchStore:
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
	return store


func _read_output_directory() -> String:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output-dir="):
			return argument.trim_prefix("--output-dir=")
	return ProjectSettings.globalize_path("res://.godot/visual-qa/ticket07")


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
