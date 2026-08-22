extends SceneTree

const CardRules = preload("res://scripts/domain/card_rules.gd")

var _failures: Array[String] = []


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	_test_cards_sort_strongest_first_with_deterministic_physical_fallbacks()
	_test_every_three_card_category_and_score()
	_test_ace_low_and_ace_high_straights()
	_test_non_consecutive_ace_sequence_is_high_card()
	_test_best_three_prefers_the_highest_score()
	_test_best_three_breaks_score_ties_by_card_strength()
	_test_best_three_breaks_suit_ties_and_does_not_mutate_the_hand()

	if _failures.is_empty():
		print("PASS: card rules tests")
		quit(0)
		return

	for failure in _failures:
		push_error(failure)
	quit(1)


func _test_cards_sort_strongest_first_with_deterministic_physical_fallbacks() -> void:
	var cards := [
		_card("clubs-ace", 14, "clubs", 0),
		_card("hearts-king", 13, "hearts", 0),
		_card("spades-ace-copy-1", 14, "spades", 1),
		_card("diamonds-ace", 14, "diamonds", 0),
		_card("hearts-ace", 14, "hearts", 0),
		_card("spades-ace-z", 14, "spades", 0),
		_card("spades-ace-a", 14, "spades", 0),
	]
	var original_ids := _card_ids(cards)

	var sorted := CardRules.sort_cards(cards)

	_expect_equal(_card_ids(sorted), [
		"hearts-ace",
		"diamonds-ace",
		"spades-ace-a",
		"spades-ace-z",
		"spades-ace-copy-1",
		"clubs-ace",
		"hearts-king",
	], "按点数、红桃/方片/黑桃/梅花、copyIndex、id 排序")
	_expect_equal(_card_ids(cards), original_ids, "排序不修改输入数组")


func _test_every_three_card_category_and_score() -> void:
	_expect_evaluation(
		[
			_card("hearts-q", 12, "hearts"),
			_card("hearts-k", 13, "hearts"),
			_card("hearts-a", 14, "hearts"),
		],
		"straight_flush",
		"同花顺",
		10
	)
	_expect_evaluation(
		[
			_card("clubs-7", 7, "clubs"),
			_card("spades-7", 7, "spades"),
			_card("hearts-7", 7, "hearts"),
		],
		"three_of_a_kind",
		"三条",
		8
	)
	_expect_evaluation(
		[
			_card("clubs-5", 5, "clubs"),
			_card("diamonds-6", 6, "diamonds"),
			_card("hearts-7", 7, "hearts"),
		],
		"straight",
		"顺子",
		5
	)
	_expect_evaluation(
		[
			_card("spades-3", 3, "spades"),
			_card("spades-8", 8, "spades"),
			_card("spades-k", 13, "spades"),
		],
		"flush",
		"同花",
		4
	)
	_expect_evaluation(
		[
			_card("clubs-9", 9, "clubs"),
			_card("diamonds-9", 9, "diamonds"),
			_card("hearts-a", 14, "hearts"),
		],
		"pair",
		"一对",
		2
	)
	_expect_evaluation(
		[
			_card("clubs-2", 2, "clubs"),
			_card("diamonds-7", 7, "diamonds"),
			_card("hearts-a", 14, "hearts"),
		],
		"high_card",
		"散牌",
		0
	)


func _test_ace_low_and_ace_high_straights() -> void:
	_expect_evaluation(
		[
			_card("hearts-a", 14, "hearts"),
			_card("clubs-2", 2, "clubs"),
			_card("diamonds-3", 3, "diamonds"),
		],
		"straight",
		"顺子",
		5
	)
	_expect_evaluation(
		[
			_card("clubs-q", 12, "clubs"),
			_card("diamonds-k", 13, "diamonds"),
			_card("hearts-a", 14, "hearts"),
		],
		"straight",
		"顺子",
		5
	)


func _test_non_consecutive_ace_sequence_is_high_card() -> void:
	_expect_evaluation(
		[
			_card("clubs-k", 13, "clubs"),
			_card("diamonds-a", 14, "diamonds"),
			_card("hearts-2", 2, "hearts"),
		],
		"high_card",
		"散牌",
		0
	)


func _test_best_three_prefers_the_highest_score() -> void:
	var result := CardRules.find_best_three([
		_card("hearts-5", 5, "hearts"),
		_card("hearts-6", 6, "hearts"),
		_card("hearts-7", 7, "hearts"),
		_card("clubs-7", 7, "clubs"),
		_card("diamonds-7", 7, "diamonds"),
	])

	_expect_equal(result.get("category"), "straight_flush", "最佳三张优先最高分牌型")
	_expect_equal(result.get("score"), 10, "最佳三张最高分")
	_expect_equal(result.get("card_ids"), ["hearts-7", "hearts-6", "hearts-5"], "最佳同花顺牌张")


func _test_best_three_breaks_score_ties_by_card_strength() -> void:
	var result := CardRules.find_best_three([
		_card("hearts-a", 14, "hearts"),
		_card("clubs-k", 13, "clubs"),
		_card("diamonds-q", 12, "diamonds"),
		_card("spades-j", 11, "spades"),
		_card("clubs-10", 10, "clubs"),
	])

	_expect_equal(result.get("category"), "straight", "多个顺子仍返回顺子")
	_expect_equal(result.get("card_ids"), ["hearts-a", "clubs-k", "diamonds-q"], "同分选择牌面更大的三张")


func _test_best_three_breaks_suit_ties_and_does_not_mutate_the_hand() -> void:
	var hand := [
		_card("diamonds-a", 14, "diamonds"),
		_card("clubs-k", 13, "clubs"),
		_card("clubs-q", 12, "clubs"),
		_card("hearts-a", 14, "hearts"),
		_card("spades-9", 9, "spades"),
	]
	var original_ids := _card_ids(hand)

	var result := CardRules.find_best_three(hand)

	_expect_equal(result.get("category"), "straight", "同点数不同花色的候选均为顺子")
	_expect_equal(result.get("card_ids"), ["hearts-a", "clubs-k", "clubs-q"], "同分按红桃优先选择")
	_expect_equal(_card_ids(hand), original_ids, "寻找最佳三张不修改输入手牌")


func _expect_evaluation(
	cards: Array,
	expected_category: String,
	expected_label: String,
	expected_score: int
) -> void:
	var result := CardRules.evaluate_three(cards)
	_expect_equal(result.get("category"), expected_category, "%s 的牌型" % expected_label)
	_expect_equal(result.get("label"), expected_label, "%s 使用牌型目录标签" % expected_label)
	_expect_equal(result.get("score"), expected_score, "%s 的分数" % expected_label)


func _card(
	card_id: String,
	rank: int,
	suit: String,
	copy_index: int = 0
) -> Dictionary:
	return {
		"id": card_id,
		"rank": rank,
		"suit": suit,
		"copy_index": copy_index,
	}


func _card_ids(cards: Array) -> Array[String]:
	var ids: Array[String] = []
	for card in cards:
		ids.append(str(card.get("id", "")))
	return ids


func _expect_equal(actual: Variant, expected: Variant, context: String) -> void:
	if actual != expected:
		_failures.append("%s：期望 %s，实际 %s" % [context, expected, actual])
