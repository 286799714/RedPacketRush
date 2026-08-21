import {
  CARD_SUITS,
  createPhysicalDeck,
  type DeckMode,
  type PhysicalCard,
} from "./cards.js";
import {
  classifyCombination,
  type CombinationCategory,
} from "./combinations.js";
import type { RandomSource } from "./random.js";

export const ACTION_DEADLINES = [15, 30, 60] as const;
export type ActionDeadlineSeconds = (typeof ACTION_DEADLINES)[number];
export type MatchPhase = "point_contest" | "actor_play" | "claim_commit";
export type MatchCommandErrorCode =
  | "invalid_phase"
  | "not_actor"
  | "invalid_play"
  | "card_not_owned"
  | "draw_pile_exhausted";

export class MatchCommandError extends Error {
  public constructor(
    public readonly code: MatchCommandErrorCode,
    message: string,
  ) {
    super(message);
    this.name = "MatchCommandError";
  }
}

export interface MatchSettings {
  readonly deckMode: DeckMode;
  readonly actionDeadlineSeconds: ActionDeadlineSeconds;
}

export interface MatchParticipant {
  readonly seatIndex: number;
  readonly participantId: string;
  readonly nickname: string;
  readonly bot: boolean;
}

export interface PublicMatchParticipant extends MatchParticipant {
  readonly score: number;
  readonly handCount: number;
}

export interface PointContestReveal {
  readonly seatIndex: number;
  readonly card: PhysicalCard;
}

export interface PointContestRoundEvent {
  readonly type: "point_contest_round";
  readonly roundNumber: number;
  readonly reveals: readonly PointContestReveal[];
  readonly tiedSeats: readonly number[];
  readonly winnerSeatIndex: number | null;
}

export interface CardsPlayedEvent {
  readonly type: "cards_played";
  readonly turnNumber: number;
  readonly actorSeatIndex: number;
  readonly cards: readonly PhysicalCard[];
  readonly category: CombinationCategory;
  readonly score: number;
}

export type PublicMatchEvent = PointContestRoundEvent | CardsPlayedEvent;

export interface PublicMatchState {
  readonly phase: MatchPhase;
  readonly actorSeatIndex: number;
  readonly firstActorSeatIndex: number;
  readonly drawPileCount: number;
  readonly playedCards: readonly PhysicalCard[];
  readonly playedCategory: CombinationCategory | null;
  readonly playedScore: number;
  readonly turnNumber: number;
  readonly participants: readonly PublicMatchParticipant[];
  readonly events: readonly PublicMatchEvent[];
}

export interface PrivateMatchState {
  readonly seatIndex: number;
  readonly participantId: string;
  readonly hand: readonly PhysicalCard[];
}

export interface MatchView {
  readonly publicState: PublicMatchState;
  readonly privateState: PrivateMatchState;
}

interface ParticipantState extends MatchParticipant {
  score: number;
  hand: PhysicalCard[];
}

const REQUIRED_SEAT_INDICES = [0, 1, 2, 3] as const;
const SUIT_STRENGTH = new Map(CARD_SUITS.map((suit, index) => [suit, index]));

export class MatchEngine {
  private readonly random: RandomSource;
  private participants: ParticipantState[] | null = null;
  private drawPile: PhysicalCard[] = [];
  private events: PublicMatchEvent[] = [];
  private firstActorSeatIndex: number | null = null;
  private actorSeatIndex: number | null = null;
  private phase: MatchPhase | null = null;
  private playedCards: PhysicalCard[] = [];
  private playedCategory: CombinationCategory | null = null;
  private playedScore = 0;
  private turnNumber = 0;

  public constructor(random: RandomSource) {
    if (!random || typeof random.nextInt !== "function") {
      throw new Error("a random source is required");
    }
    this.random = random;
  }

  public start(
    participants: readonly MatchParticipant[],
    settings: MatchSettings,
  ): void {
    if (this.participants !== null) {
      throw new Error("match has already started");
    }
    const participantStates = validateParticipants(participants);
    validateSettings(settings);

    const allCards = createPhysicalDeck(settings.deckMode);
    const contestDeck = [...allCards];
    const contest = this.runPointContest(contestDeck);
    const drawPile = [...allCards];
    this.shuffle(drawPile);
    dealOpeningHands(participantStates, drawPile);

    this.participants = participantStates;
    this.drawPile = drawPile;
    this.events = contest.events;
    this.firstActorSeatIndex = contest.winnerSeatIndex;
    this.actorSeatIndex = contest.winnerSeatIndex;
    this.phase = "point_contest";
  }

  public completePointContest(): void {
    if (this.participants === null || this.phase !== "point_contest") {
      throw new Error("point contest is not active");
    }
    this.phase = "actor_play";
  }

  public playCards(seatIndex: number, cardIds: readonly string[]): void {
    if (this.participants === null || this.phase !== "actor_play") {
      throw new MatchCommandError("invalid_phase", "actor play is not active");
    }
    if (seatIndex !== this.actorSeatIndex) {
      throw new MatchCommandError("not_actor", "only the current actor may play cards");
    }
    if (!Array.isArray(cardIds) || cardIds.length !== 3) {
      throw new MatchCommandError("invalid_play", "exactly three card identifiers are required");
    }
    if (!Array.from(cardIds).every((cardId) => (
      typeof cardId === "string" && cardId.length > 0
    ))) {
      throw new MatchCommandError("invalid_play", "card identifiers must be non-empty strings");
    }
    if (new Set(cardIds).size !== 3) {
      throw new MatchCommandError("invalid_play", "card identifiers must be distinct");
    }
    const participant = this.participants.find((candidate) => (
      candidate.seatIndex === seatIndex
    ));
    if (!participant) {
      throw new Error("seat does not participate in this match");
    }
    const cards = cardIds.map((cardId) => {
      const card = participant.hand.find((candidate) => candidate.id === cardId);
      if (!card) {
        throw new MatchCommandError("card_not_owned", "card is not owned by the actor");
      }
      return card;
    });
    if (this.drawPile.length < 3) {
      throw new MatchCommandError(
        "draw_pile_exhausted",
        "draw pile cannot replace the played cards",
      );
    }

    const combination = classifyCombination(cards);
    const playedIds = new Set(cardIds);
    participant.hand = participant.hand.filter((card) => !playedIds.has(card.id));
    for (let replacementIndex = 0; replacementIndex < 3; replacementIndex += 1) {
      const card = this.drawPile.pop();
      if (!card) {
        throw new MatchCommandError(
          "draw_pile_exhausted",
          "draw pile cannot replace the played cards",
        );
      }
      participant.hand.push(card);
    }
    participant.score += combination.score;
    this.playedCards = [...cards];
    this.playedCategory = combination.category;
    this.playedScore = combination.score;
    this.turnNumber += 1;
    this.phase = "claim_commit";
    this.events.push(Object.freeze({
      type: "cards_played",
      turnNumber: this.turnNumber,
      actorSeatIndex: seatIndex,
      cards: Object.freeze([...cards]),
      category: combination.category,
      score: combination.score,
    }));
  }

  public view(seatIndex: number): MatchView {
    if (
      this.participants === null
      || this.firstActorSeatIndex === null
      || this.actorSeatIndex === null
      || this.phase === null
    ) {
      throw new Error("match has not started");
    }
    const participant = this.participants.find((candidate) => (
      candidate.seatIndex === seatIndex
    ));
    if (!participant) {
      throw new Error("seat does not participate in this match");
    }

    const publicParticipants = this.participants.map((candidate) => Object.freeze({
      seatIndex: candidate.seatIndex,
      participantId: candidate.participantId,
      nickname: candidate.nickname,
      bot: candidate.bot,
      score: candidate.score,
      handCount: candidate.hand.length,
    }));
    const publicState: PublicMatchState = Object.freeze({
      phase: this.phase,
      actorSeatIndex: this.actorSeatIndex,
      firstActorSeatIndex: this.firstActorSeatIndex,
      drawPileCount: this.drawPile.length,
      playedCards: Object.freeze([...this.playedCards]),
      playedCategory: this.playedCategory,
      playedScore: this.playedScore,
      turnNumber: this.turnNumber,
      participants: Object.freeze(publicParticipants),
      events: Object.freeze([...this.events]),
    });
    const privateState: PrivateMatchState = Object.freeze({
      seatIndex: participant.seatIndex,
      participantId: participant.participantId,
      hand: Object.freeze([...participant.hand]),
    });
    return Object.freeze({ publicState, privateState });
  }

  private runPointContest(contestDeck: PhysicalCard[]): {
    events: PointContestRoundEvent[];
    winnerSeatIndex: number;
  } {
    let candidateSeats = [...REQUIRED_SEAT_INDICES];
    const events: PointContestRoundEvent[] = [];
    const spentCards: PhysicalCard[] = [];
    let roundNumber = 1;

    while (candidateSeats.length > 1) {
      if (contestDeck.length < candidateSeats.length) {
        contestDeck.push(...spentCards);
        spentCards.length = 0;
      }
      const reveals = candidateSeats.map((seatIndex) => {
        const card = this.drawRandomCard(contestDeck);
        spentCards.push(card);
        return Object.freeze({ seatIndex, card });
      });
      let bestCard = reveals[0].card;
      for (const reveal of reveals.slice(1)) {
        if (compareCardStrength(reveal.card, bestCard) > 0) {
          bestCard = reveal.card;
        }
      }
      const leaders = reveals
        .filter((reveal) => compareCardStrength(reveal.card, bestCard) === 0)
        .map((reveal) => reveal.seatIndex);
      const winnerSeatIndex = leaders.length === 1 ? leaders[0] : null;
      const event: PointContestRoundEvent = Object.freeze({
        type: "point_contest_round",
        roundNumber,
        reveals: Object.freeze(reveals),
        tiedSeats: Object.freeze(winnerSeatIndex === null ? [...leaders] : []),
        winnerSeatIndex,
      });
      events.push(event);
      if (winnerSeatIndex !== null) {
        return { events, winnerSeatIndex };
      }

      candidateSeats = leaders;
      roundNumber += 1;
    }

    throw new Error("point contest could not select a unique winner");
  }

  private drawRandomCard(cards: PhysicalCard[]): PhysicalCard {
    const index = this.nextRandomIndex(cards.length);
    const [card] = cards.splice(index, 1);
    if (!card) {
      throw new Error("cannot draw from an exhausted card zone");
    }
    return card;
  }

  private shuffle(cards: PhysicalCard[]): void {
    for (let index = cards.length - 1; index > 0; index -= 1) {
      const swapIndex = this.nextRandomIndex(index + 1);
      [cards[index], cards[swapIndex]] = [cards[swapIndex], cards[index]];
    }
  }

  private nextRandomIndex(maxExclusive: number): number {
    if (!Number.isSafeInteger(maxExclusive) || maxExclusive <= 0) {
      throw new Error("cannot select a random index from an empty range");
    }
    const index = this.random.nextInt(maxExclusive);
    if (!Number.isSafeInteger(index) || index < 0 || index >= maxExclusive) {
      throw new Error(`random source returned invalid index ${index} for ${maxExclusive}`);
    }
    return index;
  }
}

function validateParticipants(
  participants: readonly MatchParticipant[],
): ParticipantState[] {
  if (!Array.isArray(participants) || participants.length !== REQUIRED_SEAT_INDICES.length) {
    throw new Error("a match requires exactly four participants");
  }

  const sorted = [...participants].sort((left, right) => left.seatIndex - right.seatIndex);
  const participantIds = new Set<string>();
  for (let index = 0; index < REQUIRED_SEAT_INDICES.length; index += 1) {
    const participant = sorted[index];
    if (participant.seatIndex !== REQUIRED_SEAT_INDICES[index]) {
      throw new Error("participant seats must be unique indices 0 through 3");
    }
    if (typeof participant.participantId !== "string" || participant.participantId.length === 0) {
      throw new Error("participantId must be a non-empty string");
    }
    if (participantIds.has(participant.participantId)) {
      throw new Error("participantId values must be unique");
    }
    if (typeof participant.nickname !== "string" || participant.nickname.length === 0) {
      throw new Error("nickname must be a non-empty string");
    }
    if (typeof participant.bot !== "boolean") {
      throw new Error("bot must be a boolean");
    }
    participantIds.add(participant.participantId);
  }

  return sorted.map((participant) => ({
    seatIndex: participant.seatIndex,
    participantId: participant.participantId,
    nickname: participant.nickname,
    bot: participant.bot,
    score: 0,
    hand: [] as PhysicalCard[],
  }));
}

function validateSettings(settings: MatchSettings): void {
  if (!settings || (settings.deckMode !== "one" && settings.deckMode !== "two")) {
    throw new Error("deckMode must be one or two");
  }
  if (!ACTION_DEADLINES.some((deadline) => deadline === settings.actionDeadlineSeconds)) {
    throw new Error("actionDeadlineSeconds must be 15, 30, or 60");
  }
}

function compareCardStrength(left: PhysicalCard, right: PhysicalCard): number {
  if (left.rank !== right.rank) {
    return left.rank - right.rank;
  }
  return (SUIT_STRENGTH.get(left.suit) ?? -1) - (SUIT_STRENGTH.get(right.suit) ?? -1);
}

function dealOpeningHands(
  participants: ParticipantState[],
  drawPile: PhysicalCard[],
): void {
  const handSize = 8;
  const requiredCards = participants.length * handSize;
  if (drawPile.length < requiredCards) {
    throw new Error("deck exhausted before opening hands were complete");
  }
  for (let cardNumber = 0; cardNumber < handSize; cardNumber += 1) {
    for (const participant of participants) {
      const card = drawPile.pop();
      if (!card) {
        throw new Error("deck exhausted before opening hands were complete");
      }
      participant.hand.push(card);
    }
  }
}
