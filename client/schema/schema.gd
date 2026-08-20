# 
# THIS FILE HAS BEEN GENERATED AUTOMATICALLY
# DO NOT CHANGE IT MANUALLY UNLESS YOU KNOW WHAT YOU'RE DOING
# 
# GENERATED USING @colyseus/schema 4.0.31
# 

class ParticipantSeat extends Colyseus.Schema:
	static func definition():
		return [
			Colyseus.Schema.Field.new("seatIndex", Colyseus.Schema.UINT8),
			Colyseus.Schema.Field.new("participantId", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("nickname", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("bot", Colyseus.Schema.BOOLEAN),
			Colyseus.Schema.Field.new("ready", Colyseus.Schema.BOOLEAN),
		]

	func _to_string() -> String:
		return "ParticipantSeat(__ref_id: %s, seatIndex: %s, participantId: %s, nickname: %s, bot: %s, ready: %s)" % [self.__ref_id, self.seatIndex, self.participantId, self.nickname, self.bot, self.ready]

class GameRoomState extends Colyseus.Schema:
	static func definition():
		return [
			Colyseus.Schema.Field.new("status", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("displayName", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("deckMode", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("actionDeadlineSeconds", Colyseus.Schema.UINT8),
			Colyseus.Schema.Field.new("hostParticipantId", Colyseus.Schema.STRING),
			Colyseus.Schema.Field.new("seats", Colyseus.Schema.ARRAY, ParticipantSeat),
		]

	func _to_string() -> String:
		return "GameRoomState(__ref_id: %s, status: %s, displayName: %s, deckMode: %s, actionDeadlineSeconds: %s, hostParticipantId: %s, seats: %s)" % [self.__ref_id, self.status, self.displayName, self.deckMode, self.actionDeadlineSeconds, self.hostParticipantId, self.seats]
