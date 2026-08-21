extends RefCounted
class_name CombinationCatalog

const DEFINITIONS := {
	"high_card": {"label": "散牌", "score": 0},
	"pair": {"label": "一对", "score": 2},
	"flush": {"label": "同花", "score": 4},
	"straight": {"label": "顺子", "score": 5},
	"three_of_a_kind": {"label": "三条", "score": 8},
	"straight_flush": {"label": "同花顺", "score": 10},
}


static func is_category(category: String) -> bool:
	return DEFINITIONS.has(category)


static func label(category: String) -> String:
	var definition: Dictionary = DEFINITIONS.get(category, {})
	return str(definition.get("label", "未知"))


static func score(category: String) -> int:
	var definition: Dictionary = DEFINITIONS.get(category, {})
	return int(definition.get("score", -1))
