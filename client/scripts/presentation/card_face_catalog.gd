class_name CardFaceCatalog
extends RefCounted

const SUIT_PREFIX := {
	"clubs": "C",
	"diamonds": "D",
	"hearts": "H",
	"spades": "S",
}


static func texture_for(card: Dictionary) -> Texture2D:
	var suit_prefix := str(SUIT_PREFIX.get(str(card.get("suit", "")), ""))
	var rank := int(card.get("rank", 0))
	if suit_prefix.is_empty() or rank < 2 or rank > 14:
		return null
	var asset_rank := 1 if rank == 14 else rank
	return load("res://assets/cards/%s-%d.png" % [suit_prefix, asset_rank]) as Texture2D
