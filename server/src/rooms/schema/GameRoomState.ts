import { ArraySchema, Schema, type } from "@colyseus/schema";

import type { GameRoomMetadata } from "../GameRoom.js";

export const ROOM_SEAT_COUNT = 4;

export class ParticipantSeat extends Schema {
  @type("uint8")
  public seatIndex = 0;

  @type("string")
  public participantId = "";

  @type("string")
  public nickname = "";

  @type("boolean")
  public bot = false;

  @type("boolean")
  public ready = false;

  public constructor(seatIndex = 0) {
    super();
    this.seatIndex = seatIndex;
  }

  public occupy(participantId: string, nickname: string, bot = false): void {
    this.participantId = participantId;
    this.nickname = nickname;
    this.bot = bot;
    this.ready = bot;
  }

  public clear(): void {
    this.participantId = "";
    this.nickname = "";
    this.bot = false;
    this.ready = false;
  }
}

export class GameRoomState extends Schema {
  @type("string")
  public status = "waiting";

  @type("string")
  public displayName = "";

  @type("string")
  public deckMode = "one";

  @type("uint8")
  public actionDeadlineSeconds = 30;

  @type("string")
  public hostParticipantId = "";

  @type([ParticipantSeat])
  public seats = new ArraySchema<ParticipantSeat>();

  public constructor(metadata?: GameRoomMetadata) {
    super();
    if (metadata) {
      this.displayName = metadata.displayName;
      this.deckMode = metadata.deckMode;
      this.actionDeadlineSeconds = metadata.actionDeadlineSeconds;
    }
    for (let seatIndex = 0; seatIndex < ROOM_SEAT_COUNT; seatIndex += 1) {
      this.seats.push(new ParticipantSeat(seatIndex));
    }
  }
}
