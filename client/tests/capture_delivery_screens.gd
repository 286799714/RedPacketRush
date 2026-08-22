extends SceneTree

const MatchScreen = preload("res://scripts/match/match_screen.gd")
const LobbyScreen = preload("res://scripts/lobby/lobby_screen.gd")
const RoomScreen = preload("res://scripts/room/room_screen.gd")
const RoomStore = preload("res://scripts/room/room_store.gd")
const FakeRealtimeAdapter = preload("res://tests/fakes/fake_realtime_adapter.gd")

enum Surface { LOBBY, ROOM, MATCH }

const VIEWPORT_SIZES := [Vector2i(960, 540), Vector2i(1280, 720)]
const VALID_MATCH_PHASES := [
	"actor_play",
	"claim_commit",
	"claim_reveal",
	"award_discard",
	"final_reveal",
	"finished",
]
const SCENARIOS := [
	{
		"surface": Surface.LOBBY,
		"label": "lobby-loading-empty",
		"connection_state": "connecting",
	},
	{
		"surface": Surface.LOBBY,
		"label": "lobby-empty",
		"connection_state": "connected",
		"rooms": [],
	},
	{
		"surface": Surface.LOBBY,
		"label": "lobby-validation-error",
		"connection_state": "connected",
		"nickname": "甲",
		"endpoint": "http://invalid",
		"press_connect": true,
	},
	{
		"surface": Surface.LOBBY,
		"label": "lobby-retry",
		"connection_state": "retryable_error",
		"connection_detail": "服务器暂时不可用",
	},
	{
		"surface": Surface.LOBBY,
		"label": "lobby-populated-selected",
		"connection_state": "connected",
		"nickname": "甲",
		"rooms": [
			{"room_id": "room-a", "name": "午休局", "participant_count": 3, "seat_capacity": 4, "deck_mode": "one", "action_deadline_seconds": 30},
			{"room_id": "room-b", "name": "双牌局", "participant_count": 1, "seat_capacity": 4, "deck_mode": "two", "action_deadline_seconds": 60},
		],
		"selected_room_index": 0,
	},
	{
		"surface": Surface.ROOM,
		"label": "room-full-host",
		"room_state": {
			"room_id": "room-full",
			"local_participant_id": "human-a",
			"status": "waiting",
			"display_name": "双副牌 · 满员等待",
			"deck_mode": "two",
			"action_deadline_seconds": 30,
			"host_participant_id": "human-a",
			"seats": [
				{"seat_index": 0, "participant_id": "human-a", "nickname": "甲", "is_bot": false, "is_connected": true, "is_ready": true, "score": 0, "hand_count": 5},
				{"seat_index": 1, "participant_id": "human-b", "nickname": "乙", "is_bot": false, "is_connected": true, "is_ready": true, "score": 0, "hand_count": 5},
				{"seat_index": 2, "participant_id": "bot-c", "nickname": "机器人丙", "is_bot": true, "is_connected": true, "is_ready": true, "score": 0, "hand_count": 5},
				{"seat_index": 3, "participant_id": "bot-d", "nickname": "机器人丁", "is_bot": true, "is_connected": true, "is_ready": true, "score": 0, "hand_count": 5},
			],
		},
	},
	{
		"surface": Surface.MATCH,
		"label": "actor-play-two-deck",
		"phase": "actor_play",
		"deck_mode": "two",
		"selected_hand_indices": [0, 1, 2],
	},
	{
		"surface": Surface.MATCH,
		"label": "claim-commit-selected",
		"phase": "claim_commit",
		"selected_claim_index": 1,
	},
	{
		"surface": Surface.MATCH,
		"label": "claim-reveal-collision",
		"phase": "claim_reveal",
		"reveal_delay_seconds": 0.25,
	},
	{
		"surface": Surface.MATCH,
		"label": "award-discard-protected",
		"phase": "award_discard",
		"deck_mode": "two",
	},
	{
		"surface": Surface.MATCH,
		"label": "match-reconnecting",
		"phase": "actor_play",
		"connection_state": "reconnecting",
		"selected_hand_indices": [0, 1, 2],
	},
	{
		"surface": Surface.MATCH,
		"label": "match-participant-disconnected",
		"phase": "actor_play",
		"participant_overrides": [
			{"seat_index": 1, "is_connected": false},
		],
	},
	{
		"surface": Surface.MATCH,
		"label": "match-bot-takeover",
		"phase": "actor_play",
		"participant_overrides": [
			{"seat_index": 1, "is_connected": false, "is_bot": true},
		],
	},
	{
		"surface": Surface.MATCH,
		"label": "match-validation-error",
		"phase": "actor_play",
		"selected_hand_indices": [0, 1, 2],
		"error_code": "invalid_play",
		"error_message": "出牌失败：请选择三张不同的手牌",
	},
	{"surface": Surface.MATCH, "label": "final-reveal", "phase": "final_reveal"},
	{"surface": Surface.MATCH, "label": "finished", "phase": "finished"},
]


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
	var acquired_card_ids: Array[String] = []
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

	func get_acquired_card_ids() -> Array[String]:
		return acquired_card_ids.duplicate()

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
	if not _validate_scenarios():
		quit(1)
		return
	if "--validate-only" in OS.get_cmdline_user_args():
		print("PASS: validated %d delivery capture scenarios" % SCENARIOS.size())
		quit(0)
		return

	var output_directory := _read_output_directory()
	var error := DirAccess.make_dir_recursive_absolute(output_directory)
	if error != OK:
		push_error("could not create screenshot directory: %s" % error_string(error))
		quit(1)
		return
	for viewport_size in VIEWPORT_SIZES:
		for spec in SCENARIOS:
			if not await _capture_scenario(spec, viewport_size, output_directory):
				quit(1)
				return

	print("PASS: captured %d nonblank delivery screen states at %d viewport sizes in %s" % [
		SCENARIOS.size(),
		VIEWPORT_SIZES.size(),
		output_directory,
	])
	quit(0)


func _validate_scenarios() -> bool:
	var seen_labels: Dictionary = {}
	for spec in SCENARIOS:
		if not spec.has_all(["surface", "label"]):
			push_error("delivery capture scenario is missing surface or label: %s" % spec)
			return false
		var surface: int = spec["surface"]
		var label: String = spec["label"]
		if label.is_empty() or seen_labels.has(label):
			push_error("delivery capture scenario label is empty or duplicated: %s" % label)
			return false
		match surface:
			Surface.LOBBY:
				if not spec.has("connection_state") or spec.has("phase"):
					push_error("lobby capture scenario has invalid state data: %s" % spec)
					return false
			Surface.ROOM:
				if not spec.has("room_state") or spec.has("phase"):
					push_error("room capture scenario has invalid state data: %s" % spec)
					return false
			Surface.MATCH:
				if not spec.has("phase") or spec["phase"] not in VALID_MATCH_PHASES:
					push_error("match capture scenario has an invalid phase: %s" % spec)
					return false
			_:
				push_error("delivery capture scenario has an invalid surface: %s" % spec)
				return false
		seen_labels[label] = true
	return true


func _capture_scenario(
	spec: Dictionary,
	viewport_size: Vector2i,
	output_directory: String
) -> bool:
	var surface: int = spec["surface"]
	match surface:
		Surface.LOBBY:
			return await _capture_lobby_state(spec, viewport_size, output_directory)
		Surface.ROOM:
			return await _capture_room_state(spec, viewport_size, output_directory)
		Surface.MATCH:
			return await _capture_match_state(spec, viewport_size, output_directory)
	push_error("unsupported delivery capture surface: %s" % surface)
	return false


func _create_capture_viewport(viewport_size: Vector2i) -> SubViewport:
	var viewport := SubViewport.new()
	viewport.size = viewport_size
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	root.add_child(viewport)
	return viewport


func _capture_lobby_state(
	spec: Dictionary,
	viewport_size: Vector2i,
	output_directory: String
) -> bool:
	var viewport := _create_capture_viewport(viewport_size)
	var adapter := FakeRealtimeAdapter.new()
	var screen := LobbyScreen.new()
	screen.set_realtime_adapter(adapter)
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(viewport_size)
	viewport.add_child(screen)
	await process_frame
	await process_frame
	adapter.publish_connection_state(
		str(spec["connection_state"]),
		str(spec.get("connection_detail", ""))
	)
	if spec.has("nickname"):
		screen._nickname_input.text = str(spec["nickname"])
	if spec.has("endpoint"):
		screen._endpoint_input.text = str(spec["endpoint"])
	if bool(spec.get("press_connect", false)):
		screen._connect_button.pressed.emit()
	if spec.has("rooms"):
		var rooms: Array[Dictionary] = []
		for room in spec["rooms"]:
			rooms.append(room)
		adapter.publish_rooms(rooms)
	if spec.has("selected_room_index"):
		await process_frame
		var root_item := screen._room_tree.get_root()
		var selected_item := root_item.get_first_child() if root_item != null else null
		for index in range(int(spec["selected_room_index"])):
			if selected_item != null:
				selected_item = selected_item.get_next()
		if selected_item != null:
			screen._room_tree.set_selected(selected_item, 0)
			screen._on_room_selected()
	await process_frame
	await process_frame
	return await _save_capture(viewport, output_directory, str(spec["label"]), viewport_size)


func _capture_room_state(
	spec: Dictionary,
	viewport_size: Vector2i,
	output_directory: String
) -> bool:
	var viewport := _create_capture_viewport(viewport_size)
	var adapter := FakeRealtimeAdapter.new()
	var store := RoomStore.new(adapter)
	var screen := RoomScreen.new()
	screen.set_room_store(store)
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(viewport_size)
	viewport.add_child(screen)
	await process_frame
	adapter.publish_game_room_state(spec["room_state"])
	await process_frame
	await process_frame
	return await _save_capture(viewport, output_directory, str(spec["label"]), viewport_size)


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


func _capture_match_state(
	spec: Dictionary,
	viewport_size: Vector2i,
	output_directory: String
) -> bool:
	var viewport := _create_capture_viewport(viewport_size)
	var store := _make_store(spec)
	var screen := MatchScreen.new()
	screen.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	screen.size = Vector2(viewport_size)
	screen.set_match_store(store)
	viewport.add_child(screen)
	await process_frame
	await process_frame
	if spec.has("error_message"):
		screen._on_action_failed(
			str(spec.get("error_code", "visual_capture_error")),
			str(spec["error_message"])
		)
		await process_frame

	for raw_index in spec.get("selected_hand_indices", []):
		var index := int(raw_index)
		var card_button := screen.find_child("HandCard%d" % index, true, false) as Button
		if card_button == null:
			push_error("match capture could not find hand card %d" % index)
			viewport.queue_free()
			await process_frame
			return false
		card_button.button_pressed = true
	await process_frame

	if spec.has("selected_claim_index"):
		var claim_index := int(spec["selected_claim_index"])
		var claim_card := screen.find_child("ClaimCard%d" % claim_index, true, false) as Button
		if claim_card == null:
			push_error("match capture could not find played card %d" % claim_index)
			viewport.queue_free()
			await process_frame
			return false
		claim_card.button_pressed = true
		await process_frame

	var reveal_delay_seconds := float(spec.get("reveal_delay_seconds", 0.0))
	if reveal_delay_seconds > 0.0:
		await create_timer(reveal_delay_seconds).timeout

	for raw_group in spec.get("final_selection", []):
		var group: Dictionary = raw_group
		var group_button := _find_button(screen, str(group["group_button"]))
		if group_button == null:
			push_error("final selection capture could not find group button: %s" % group["group_button"])
			viewport.queue_free()
			await process_frame
			return false
		group_button.button_pressed = true
		await process_frame
		for raw_fragment in group["card_fragments"]:
			var fragment := str(raw_fragment)
			var card_button := _find_button_with_content(screen, fragment)
			if card_button == null:
				push_error("final selection capture could not find card: %s" % fragment)
				viewport.queue_free()
				await process_frame
				return false
			card_button.button_pressed = true
			await process_frame

	return await _save_capture(viewport, output_directory, str(spec["label"]), viewport_size)


func _make_store(spec: Dictionary) -> VisualMatchStore:
	var store := VisualMatchStore.new()
	var phase := str(spec["phase"])
	store.phase = phase
	store.participants = [
		_seat(0, "human-a", "甲", false, 10, 5),
		_seat(1, "human-b", "乙", false, 4, 5),
		_seat(2, "bot-c", "机器人丙", true, 2, 5),
		_seat(3, "bot-d", "机器人丁", true, 1, 5),
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
		_card("local-8", 8, "diamonds", 0),
		_card("local-q", 12, "hearts", 0),
		_card("local-k", 13, "hearts", 0),
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
	if phase in ["final_reveal", "finished"]:
		store.actor_seat_index = -1
		store.draw_pile_count = 0
		store.sealed_card_count = 2
		store.local_hand = _final_hand()
	if phase in ["final_reveal", "finished"]:
		store.final_committed = true
		store.final_groups = [
			["final-clubs-2", "final-clubs-3", "final-clubs-4"],
		]
		store.participants = [
			_seat(0, "human-a", "甲", false, 22, 5),
			_seat(1, "human-b", "乙", false, 25, 5),
			_seat(2, "bot-c", "机器人丙", true, 25, 5),
			_seat(3, "bot-d", "机器人丁", true, 10, 5),
		]
		store.final_results = _final_results()
		store.winner_seat_indexes = [1, 2]
		store.final_events = [{
			"type": "final_settlement",
			"results": store.final_results,
			"winner_seat_indexes": store.winner_seat_indexes,
		}]
	if phase == "award_discard":
		var awarded_card := _card("award-hearts-a-copy-1", 14, "hearts", 1)
		store.local_hand = [
			_card("original-clubs-2", 2, "clubs", 0),
			_card("original-spades-3", 3, "spades", 0),
			awarded_card,
			_card("original-diamonds-4", 4, "diamonds", 0),
			_card("original-hearts-5", 5, "hearts", 0),
			_card("original-clubs-6", 6, "clubs", 0),
		]
		store.acquired_card_ids = [str(awarded_card["id"])]
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
	store.connection_state = str(spec.get("connection_state", store.connection_state))
	store.deck_mode = str(spec.get("deck_mode", store.deck_mode))
	for raw_override in spec.get("participant_overrides", []):
		var participant_override: Dictionary = raw_override
		var seat_index := int(participant_override["seat_index"])
		if seat_index < 0 or seat_index >= store.participants.size():
			continue
		var participant := store.participants[seat_index].duplicate(true)
		for key in participant_override:
			if key != "seat_index":
				participant[key] = participant_override[key]
		store.participants[seat_index] = participant
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
		_card("final-diamonds-10", 10, "diamonds", 0),
		_card("final-hearts-a", 14, "hearts", 0),
	]


func _final_results() -> Array[Dictionary]:
	return [
		_final_result(0, 10, "straight_flush", 10, "seat0"),
		_final_result(1, 5, "straight", 5, "seat1"),
		_final_result(2, 8, "three_of_a_kind", 8, "seat2"),
		_final_result(3, 4, "flush", 4, "seat3"),
	]


func _final_result(
	seat_index: int,
	total_score: int,
	category: String,
	score: int,
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
				"category": category,
				"score": score,
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
