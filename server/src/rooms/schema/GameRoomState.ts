import { ArraySchema, Schema, type } from "@colyseus/schema";

import type { DeckMode, PhysicalCard } from "../../match/cards.js";
import type {
  ActionDeadlineSeconds,
  CardDiscardedEvent,
  CardsPlayedEvent,
  ClaimAward,
  ClaimsResolvedEvent,
  FinalResult,
  FinalSettlementEvent,
  PointContestRoundEvent,
  RevealedClaim,
} from "../../match/MatchEngine.js";
import type { FinalCombination } from "../../match/finalSettlement.js";
import type { GameRoomMetadata, GameRoomStatus } from "../GameRoom.js";

export const ROOM_SEAT_COUNT = 4;

export class PublicCardState extends Schema {
  @type("string")
  public id = "";

  @type("uint8")
  public rank = 0;

  @type("string")
  public suit = "";

  @type("uint8")
  public copyIndex = 0;

  public constructor(card?: PhysicalCard) {
    super();
    if (card) {
      this.id = card.id;
      this.rank = card.rank;
      this.suit = card.suit;
      this.copyIndex = card.copyIndex;
    }
  }
}

export class PointContestRevealState extends Schema {
  @type("uint8")
  public seatIndex = 0;

  @type(PublicCardState)
  public card = new PublicCardState();

  public constructor(seatIndex = 0, card?: PhysicalCard) {
    super();
    this.seatIndex = seatIndex;
    if (card) {
      this.card = new PublicCardState(card);
    }
  }
}

export class PointContestRoundState extends Schema {
  @type("uint8")
  public roundIndex = 0;

  @type([PointContestRevealState])
  public reveals = new ArraySchema<PointContestRevealState>();

  @type(["uint8"])
  public tiedSeatIndexes = new ArraySchema<number>();

  @type("int8")
  public winnerSeatIndex = -1;

  public constructor(event?: PointContestRoundEvent) {
    super();
    if (!event) {
      return;
    }
    this.roundIndex = event.roundNumber - 1;
    for (const reveal of event.reveals) {
      this.reveals.push(new PointContestRevealState(reveal.seatIndex, reveal.card));
    }
    this.tiedSeatIndexes.push(...event.tiedSeats);
    this.winnerSeatIndex = event.winnerSeatIndex ?? -1;
  }
}

export class PlayEventState extends Schema {
  @type("uint16")
  public turnNumber = 0;

  @type("uint8")
  public actorSeatIndex = 0;

  @type([PublicCardState])
  public cards = new ArraySchema<PublicCardState>();

  @type("string")
  public category = "";

  @type("uint8")
  public score = 0;

  public constructor(event?: CardsPlayedEvent) {
    super();
    if (!event) {
      return;
    }
    this.turnNumber = event.turnNumber;
    this.actorSeatIndex = event.actorSeatIndex;
    for (const card of event.cards) {
      this.cards.push(new PublicCardState(card));
    }
    this.category = event.category;
    this.score = event.score;
  }
}

export class RevealedClaimState extends Schema {
  @type("uint8")
  public seatIndex = 0;

  @type("boolean")
  public passed = false;

  @type("string")
  public cardId = "";

  public constructor(claim?: RevealedClaim) {
    super();
    if (claim) {
      this.seatIndex = claim.seatIndex;
      this.passed = claim.cardId === null;
      this.cardId = claim.cardId ?? "";
    }
  }
}

export class ClaimAwardState extends Schema {
  @type("uint8")
  public seatIndex = 0;

  @type(PublicCardState)
  public card = new PublicCardState();

  @type("string")
  public source = "";

  public constructor(award?: ClaimAward) {
    super();
    if (award) {
      this.seatIndex = award.seatIndex;
      this.card = new PublicCardState(award.card);
      this.source = award.source;
    }
  }
}

export class ClaimsResolvedEventState extends Schema {
  @type("uint16")
  public turnNumber = 0;

  @type([RevealedClaimState])
  public claims = new ArraySchema<RevealedClaimState>();

  @type([ClaimAwardState])
  public awards = new ArraySchema<ClaimAwardState>();

  @type([PublicCardState])
  public discardedCards = new ArraySchema<PublicCardState>();

  public constructor(event?: ClaimsResolvedEvent) {
    super();
    if (!event) {
      return;
    }
    this.turnNumber = event.turnNumber;
    for (const claim of event.claims) {
      this.claims.push(new RevealedClaimState(claim));
    }
    for (const award of event.awards) {
      this.awards.push(new ClaimAwardState(award));
    }
    for (const card of event.discardedCards) {
      this.discardedCards.push(new PublicCardState(card));
    }
  }
}

export class CardDiscardedEventState extends Schema {
  @type("uint16")
  public turnNumber = 0;

  @type("uint8")
  public seatIndex = 0;

  @type(PublicCardState)
  public card = new PublicCardState();

  public constructor(event?: CardDiscardedEvent) {
    super();
    if (event) {
      this.turnNumber = event.turnNumber;
      this.seatIndex = event.seatIndex;
      this.card = new PublicCardState(event.card);
    }
  }
}

export class FinalCombinationState extends Schema {
  @type([PublicCardState])
  public cards = new ArraySchema<PublicCardState>();

  @type("string")
  public category = "";

  @type("uint8")
  public score = 0;

  public constructor(group?: FinalCombination) {
    super();
    if (!group) {
      return;
    }
    for (const card of group.cards) {
      this.cards.push(new PublicCardState(card));
    }
    this.category = group.category;
    this.score = group.score;
  }
}

export class FinalResultState extends Schema {
  @type("uint8")
  public seatIndex = 0;

  @type([FinalCombinationState])
  public groups = new ArraySchema<FinalCombinationState>();

  @type("uint8")
  public totalScore = 0;

  public constructor(result?: FinalResult) {
    super();
    if (!result) {
      return;
    }
    this.seatIndex = result.seatIndex;
    for (const group of result.groups) {
      this.groups.push(new FinalCombinationState(group));
    }
    this.totalScore = result.totalScore;
  }
}

export class FinalSettlementEventState extends Schema {
  @type([FinalResultState])
  public results = new ArraySchema<FinalResultState>();

  @type(["uint8"])
  public winnerSeatIndexes = new ArraySchema<number>();

  public constructor(event?: FinalSettlementEvent) {
    super();
    if (!event) {
      return;
    }
    for (const result of event.results) {
      this.results.push(new FinalResultState(result));
    }
    this.winnerSeatIndexes.push(...event.winnerSeatIndexes);
  }
}

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

  @type("uint16")
  public score = 0;

  @type("uint8")
  public handCount = 0;

  public constructor(seatIndex = 0) {
    super();
    this.seatIndex = seatIndex;
  }

  public occupy(participantId: string, nickname: string, bot = false): void {
    this.participantId = participantId;
    this.nickname = nickname;
    this.bot = bot;
    this.ready = bot;
    this.score = 0;
    this.handCount = 0;
  }

  public clear(): void {
    this.participantId = "";
    this.nickname = "";
    this.bot = false;
    this.ready = false;
    this.score = 0;
    this.handCount = 0;
  }
}

export class GameRoomState extends Schema {
  @type("string")
  public status: GameRoomStatus = "waiting";

  @type("string")
  public displayName = "";

  @type("string")
  public deckMode: DeckMode = "one";

  @type("uint8")
  public actionDeadlineSeconds: ActionDeadlineSeconds = 30;

  @type("string")
  public hostParticipantId = "";

  @type("string")
  public phase = "";

  @type("int8")
  public actorSeatIndex = -1;

  @type("int8")
  public firstActorSeatIndex = -1;

  @type("uint8")
  public drawPileCount = 0;

  @type("uint16")
  public turnNumber = 0;

  @type([PublicCardState])
  public playedCards = new ArraySchema<PublicCardState>();

  @type("string")
  public playedCategory = "";

  @type("uint8")
  public playedScore = 0;

  @type([RevealedClaimState])
  public revealedClaims = new ArraySchema<RevealedClaimState>();

  @type([ClaimAwardState])
  public claimAwards = new ArraySchema<ClaimAwardState>();

  @type([PublicCardState])
  public discardedCards = new ArraySchema<PublicCardState>();

  @type("uint8")
  public sealedCardCount = 0;

  @type(["uint8"])
  public pendingDiscardSeatIndexes = new ArraySchema<number>();

  @type([FinalResultState])
  public finalResults = new ArraySchema<FinalResultState>();

  @type(["uint8"])
  public winnerSeatIndexes = new ArraySchema<number>();

  @type([ParticipantSeat])
  public seats = new ArraySchema<ParticipantSeat>();

  @type([PointContestRoundState])
  public contestRounds = new ArraySchema<PointContestRoundState>();

  @type([PlayEventState])
  public playEvents = new ArraySchema<PlayEventState>();

  @type([ClaimsResolvedEventState])
  public claimEvents = new ArraySchema<ClaimsResolvedEventState>();

  @type([CardDiscardedEventState])
  public discardEvents = new ArraySchema<CardDiscardedEventState>();

  @type([FinalSettlementEventState])
  public finalEvents = new ArraySchema<FinalSettlementEventState>();

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
