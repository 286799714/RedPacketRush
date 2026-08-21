extends RefCounted
class_name CombinationCatalog

const DEFINITIONS := {
	"high_card": "散牌",
	"pair": "一对",
	"flush": "同花",
	"straight": "顺子",
	"three_of_a_kind": "三条",
	"straight_flush": "同花顺",
}


static func is_category(category: String) -> bool:
	return DEFINITIONS.has(category)


static func label(category: String) -> String:
	return str(DEFINITIONS.get(category, "未知"))
