extends RefCounted
class_name CardRules

const CombinationCatalog = preload("res://scripts/domain/combination_catalog.gd")

const SUIT_STRENGTH := {
	"clubs": 1,
	"spades": 2,
	"diamonds": 3,
	"hearts": 4,
}

const CATEGORY_SCORES := {
	"high_card": 0,
	"pair": 2,
	"flush": 4,
	"straight": 5,
	"three_of_a_kind": 8,
	"straight_flush": 10,
}


## Returns deep-copied cards ordered strongest-to-weakest. Physical duplicates
## use the lower copy index, then the lexicographically lower id, as fallbacks.
static func sort_cards(cards: Array) -> Array[Dictionary]:
	var sorted_cards: Array[Dictionary] = []
	for value in cards:
		if value is Dictionary:
			var card: Dictionary = value
			sorted_cards.append(card.duplicate(true))
	sorted_cards.sort_custom(_card_precedes)
	return sorted_cards


## Evaluates exactly three cards. The result contains cards, card_ids, category,
## the CombinationCatalog label, and score. Invalid input returns an empty result.
static func evaluate_three(cards: Array) -> Dictionary:
	if cards.size() != 3 or not _all_cards_valid(cards):
		return {}

	var sorted_cards := sort_cards(cards)
	var ranks: Array[int] = []
	var unique_ranks := {}
	for card in sorted_cards:
		var rank := int(card.get("rank", 0))
		ranks.append(rank)
		unique_ranks[rank] = true
	ranks.sort()

	var is_flush := (
		str(sorted_cards[0].get("suit", "")) == str(sorted_cards[1].get("suit", ""))
		and str(sorted_cards[1].get("suit", "")) == str(sorted_cards[2].get("suit", ""))
	)
	var is_straight := (
		(ranks[1] == ranks[0] + 1 and ranks[2] == ranks[1] + 1)
		or ranks == [2, 3, 14]
	)
	var category := "high_card"
	if is_straight and is_flush:
		category = "straight_flush"
	elif unique_ranks.size() == 1:
		category = "three_of_a_kind"
	elif is_straight:
		category = "straight"
	elif is_flush:
		category = "flush"
	elif unique_ranks.size() == 2:
		category = "pair"

	var card_ids: Array[String] = []
	for card in sorted_cards:
		card_ids.append(str(card.get("id", "")))
	return {
		"cards": sorted_cards,
		"card_ids": card_ids,
		"category": category,
		"label": CombinationCatalog.label(category),
		"score": int(CATEGORY_SCORES[category]),
	}


## Evaluates every three-card subset and returns the highest-scoring result.
## Equal scores are resolved by comparing sorted cards strongest-to-weakest.
static func find_best_three(hand: Array) -> Dictionary:
	if hand.size() < 3 or not _all_cards_valid(hand):
		return {}

	var sorted_hand := sort_cards(hand)
	var best: Dictionary = {}
	for first_index in range(sorted_hand.size() - 2):
		for second_index in range(first_index + 1, sorted_hand.size() - 1):
			for third_index in range(second_index + 1, sorted_hand.size()):
				var candidate := evaluate_three([
					sorted_hand[first_index],
					sorted_hand[second_index],
					sorted_hand[third_index],
				])
				if best.is_empty() or _evaluation_precedes(candidate, best):
					best = candidate
	return best.duplicate(true)


static func _all_cards_valid(cards: Array) -> bool:
	for value in cards:
		if value is not Dictionary:
			return false
		var card: Dictionary = value
		var rank := int(card.get("rank", 0))
		var suit := str(card.get("suit", ""))
		if str(card.get("id", "")).is_empty():
			return false
		if rank < 2 or rank > 14 or not SUIT_STRENGTH.has(suit):
			return false
	return true


static func _evaluation_precedes(left: Dictionary, right: Dictionary) -> bool:
	var left_score := int(left.get("score", -1))
	var right_score := int(right.get("score", -1))
	if left_score != right_score:
		return left_score > right_score

	var left_cards: Array = left.get("cards", [])
	var right_cards: Array = right.get("cards", [])
	for index in range(mini(left_cards.size(), right_cards.size())):
		var comparison := _compare_cards(left_cards[index], right_cards[index])
		if comparison != 0:
			return comparison < 0
	return left_cards.size() > right_cards.size()


static func _card_precedes(left: Dictionary, right: Dictionary) -> bool:
	return _compare_cards(left, right) < 0


static func _compare_cards(left: Dictionary, right: Dictionary) -> int:
	var left_rank := int(left.get("rank", 0))
	var right_rank := int(right.get("rank", 0))
	if left_rank != right_rank:
		return -1 if left_rank > right_rank else 1

	var left_suit_strength := int(SUIT_STRENGTH.get(str(left.get("suit", "")), 0))
	var right_suit_strength := int(SUIT_STRENGTH.get(str(right.get("suit", "")), 0))
	if left_suit_strength != right_suit_strength:
		return -1 if left_suit_strength > right_suit_strength else 1

	var left_copy_index := int(left.get("copy_index", left.get("copyIndex", 0)))
	var right_copy_index := int(right.get("copy_index", right.get("copyIndex", 0)))
	if left_copy_index != right_copy_index:
		return -1 if left_copy_index < right_copy_index else 1

	var left_id := str(left.get("id", ""))
	var right_id := str(right.get("id", ""))
	if left_id == right_id:
		return 0
	return -1 if left_id < right_id else 1
