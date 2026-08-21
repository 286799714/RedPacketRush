# 
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY
# DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
# 
# GENERATED USING @colyseus/schema 4.0.31
# 

class PublicCardState extends Colyseus.Schema:
	static func definition():
		return [
			Colyseus.Schema.Field.new("id", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("rank", Colyseus.Schema.UINT8),
			Colyseus.Schema.Field.new("suit", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("copyIndex", Colyseus.Schema.UINT8),
		]

	func _to_string() -> String:
		return "PublicCardState(__ref_id: %s, id: %s, rank: %s, suit: %s, copyIndex: %s)" % [self.__ref_id, self.id, self.rank, self.suit, self.copyIndex]

class PointContestRevealState extends Colyseus.Schema:
	static func definition():
		return [
			Colyseus.Schema.Field.new("seatIndex", Colyseus.Schema.UINT8),
			Colyseus.Schema.Field.new("card", Colyseus.Schema.REF, PublicCardState),
		]

	func _to_string() -> String:
		return "PointContestRevealState(__ref_id: %s, seatIndex: %s, card: %s)" % [self.__ref_id, self.seatIndex, self.card]

class PointContestRoundState extends Colyseus.Schema:
	static func definition():
		return [
			Colyseus.Schema.Field.new("roundIndex", Colyseus.Schema.UINT8),
			Colyseus.Schema.Field.new("reveals", Colyseus.Schema.ARRAY, PointContestRevealState),
			Colyseus.Schema.Field.new("tiedSeatIndexes", Colyseus.Schema.ARRAY, Colyseus.Schema.UINT8),
			Colyseus.Schema.Field.new("winnerSeatIndex", Colyseus.Schema.INT8),
		]

	func _to_string() -> String:
		return "PointContestRoundState(__ref_id: %s, roundIndex: %s, reveals: %s, tiedSeatIndexes: %s, winnerSeatIndex: %s)" % [self.__ref_id, self.roundIndex, self.reveals, self.tiedSeatIndexes, self.winnerSeatIndex]

class PlayEventState extends Colyseus.Schema:
	static func definition():
		return [
			Colyseus.Schema.Field.new("turnNumber", Colyseus.Schema.UINT16),
			Colyseus.Schema.Field.new("actorSeatIndex", Colyseus.Schema.UINT8),
			Colyseus.Schema.Field.new("cards", Colyseus.Schema.ARRAY, PublicCardState),
			Colyseus.Schema.Field.new("category", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("score", Colyseus.Schema.UINT8),
		]

	func _to_string() -> String:
		return "PlayEventState(__ref_id: %s, turnNumber: %s, actorSeatIndex: %s, cards: %s, category: %s, score: %s)" % [self.__ref_id, self.turnNumber, self.actorSeatIndex, self.cards, self.category, self.score]

class ParticipantSeat extends Colyseus.Schema:
	static func definition():
		return [
			Colyseus.Schema.Field.new("seatIndex", Colyseus.Schema.UINT8),
			Colyseus.Schema.Field.new("participantId", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("nickname", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("bot", Colyseus.Schema.BOOLEAN),
			Colyseus.Schema.Field.new("ready", Colyseus.Schema.BOOLEAN),
			Colyseus.Schema.Field.new("score", Colyseus.Schema.UINT16),
			Colyseus.Schema.Field.new("handCount", Colyseus.Schema.UINT8),
		]

	func _to_string() -> String:
		return "ParticipantSeat(__ref_id: %s, seatIndex: %s, participantId: %s, nickname: %s, bot: %s, ready: %s, score: %s, handCount: %s)" % [self.__ref_id, self.seatIndex, self.participantId, self.nickname, self.bot, self.ready, self.score, self.handCount]

class GameRoomState extends Colyseus.Schema:
	static func definition():
		return [
			Colyseus.Schema.Field.new("status", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("displayName", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("deckMode", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("actionDeadlineSeconds", Colyseus.Schema.UINT8),
			Colyseus.Schema.Field.new("hostParticipantId", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("phase", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("actorSeatIndex", Colyseus.Schema.INT8),
			Colyseus.Schema.Field.new("firstActorSeatIndex", Colyseus.Schema.INT8),
			Colyseus.Schema.Field.new("drawPileCount", Colyseus.Schema.UINT8),
			Colyseus.Schema.Field.new("turnNumber", Colyseus.Schema.UINT16),
			Colyseus.Schema.Field.new("playedCards", Colyseus.Schema.ARRAY, PublicCardState),
			Colyseus.Schema.Field.new("playedCategory", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("playedScore", Colyseus.Schema.UINT8),
			Colyseus.Schema.Field.new("seats", Colyseus.Schema.ARRAY, ParticipantSeat),
			Colyseus.Schema.Field.new("contestRounds", Colyseus.Schema.ARRAY, PointContestRoundState),
			Colyseus.Schema.Field.new("playEvents", Colyseus.Schema.ARRAY, PlayEventState),
		]

	func _to_string() -> String:
		return "GameRoomState(__ref_id: %s, status: %s, displayName: %s, deckMode: %s, actionDeadlineSeconds: %s, hostParticipantId: %s, phase: %s, actorSeatIndex: %s, firstActorSeatIndex: %s, drawPileCount: %s, turnNumber: %s, playedCards: %s, playedCategory: %s, playedScore: %s, seats: %s, contestRounds: %s, playEvents: %s)" % [self.__ref_id, self.status, self.displayName, self.deckMode, self.actionDeadlineSeconds, self.hostParticipantId, self.phase, self.actorSeatIndex, self.firstActorSeatIndex, self.drawPileCount, self.turnNumber, self.playedCards, self.playedCategory, self.playedScore, self.seats, self.contestRounds, self.playEvents]
