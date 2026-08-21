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
import {
  evaluateFinalSelection,
  findBestFinalSelection,
  type EvaluatedFinalSelection,
  type FinalCombination,
} from "./finalSettlement.js";
import type { RandomSource } from "./random.js";

export const ACTION_DEADLINES = [15, 30, 60] as const;
export type ActionDeadlineSeconds = (typeof ACTION_DEADLINES)[number];
export type MatchPhase =
  | "point_contest"
  | "actor_play"
  | "claim_commit"
  | "claim_reveal"
  | "award_discard"
  | "final_commit"
  | "final_reveal"
  | "finished";
export type MatchCommandErrorCode =
  | "invalid_phase"
  | "not_actor"
  | "invalid_play"
  | "card_not_owned"
  | "draw_pile_exhausted"
  | "actor_cannot_claim"
  | "invalid_claim"
  | "claim_already_committed"
  | "invalid_discard"
  | "discard_not_required"
  | "awarded_card_protected"
  | "stale_turn"
  | "invalid_final_selection"
  | "final_selection_already_committed";

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

export interface RevealedClaim {
  readonly seatIndex: number;
  readonly cardId: string | null;
}

export interface ClaimAward {
  readonly seatIndex: number;
  readonly card: PhysicalCard;
  readonly source: "unique" | "collision";
}

export interface ClaimsResolvedEvent {
  readonly type: "claims_resolved";
  readonly turnNumber: number;
  readonly claims: readonly RevealedClaim[];
  readonly awards: readonly ClaimAward[];
  readonly discardedCards: readonly PhysicalCard[];
}

export interface CardDiscardedEvent {
  readonly type: "card_discarded";
  readonly turnNumber: number;
  readonly seatIndex: number;
  readonly card: PhysicalCard;
}

export interface FinalResult {
  readonly seatIndex: number;
  readonly groups: readonly FinalCombination[];
  readonly totalScore: number;
}

export interface FinalSettlementEvent {
  readonly type: "final_settlement";
  readonly results: readonly FinalResult[];
  readonly winnerSeatIndexes: readonly number[];
}

export type PublicMatchEvent =
  | PointContestRoundEvent
  | CardsPlayedEvent
  | ClaimsResolvedEvent
  | CardDiscardedEvent
  | FinalSettlementEvent;

export interface PublicMatchState {
  readonly phase: MatchPhase;
  readonly actorSeatIndex: number;
  readonly firstActorSeatIndex: number;
  readonly drawPileCount: number;
  readonly playedCards: readonly PhysicalCard[];
  readonly playedCategory: CombinationCategory | null;
  readonly playedScore: number;
  readonly turnNumber: number;
  readonly revealedClaims: readonly RevealedClaim[];
  readonly claimAwards: readonly ClaimAward[];
  readonly discardedCards: readonly PhysicalCard[];
  readonly sealedCardCount: number;
  readonly pendingDiscardSeatIndexes: readonly number[];
  readonly finalResults: readonly FinalResult[];
  readonly winnerSeatIndexes: readonly number[];
  readonly participants: readonly PublicMatchParticipant[];
  readonly events: readonly PublicMatchEvent[];
}

export interface PrivateMatchState {
  readonly seatIndex: number;
  readonly participantId: string;
  readonly hand: readonly PhysicalCard[];
  readonly claimCommitted: boolean;
  readonly claimCardId: string | null;
  readonly finalCommitted: boolean;
  readonly finalGroups: readonly (readonly string[])[];
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
  private claimChoices = new Map<number, string | null>();
  private revealedClaims: RevealedClaim[] = [];
  private claimAwards: ClaimAward[] = [];
  private discardedCards: PhysicalCard[] = [];
  private sealedCards: PhysicalCard[] = [];
  private pendingDiscardSeatIndexes = new Set<number>();
  private protectedAwardCardIds = new Map<number, string>();
  private finalSelections = new Map<number, EvaluatedFinalSelection>();
  private finalResults: FinalResult[] = [];
  private winnerSeatIndexes: number[] = [];
  private configuredCardCount = 0;

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
    this.configuredCardCount = allCards.length;
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

  public commitClaim(seatIndex: number, cardId: string | null): void {
    if (this.participants === null || this.phase !== "claim_commit") {
      throw new MatchCommandError("invalid_phase", "claim commit is not active");
    }
    if (seatIndex === this.actorSeatIndex) {
      throw new MatchCommandError("actor_cannot_claim", "the current actor cannot claim cards");
    }
    if (!this.participants.some((participant) => participant.seatIndex === seatIndex)) {
      throw new MatchCommandError("invalid_claim", "seat cannot commit a claim");
    }
    if (this.claimChoices.has(seatIndex)) {
      throw new MatchCommandError("claim_already_committed", "claim has already been committed");
    }
    if (
      cardId !== null
      && (
        typeof cardId !== "string"
        || !this.playedCards.some((card) => card.id === cardId)
      )
    ) {
      throw new MatchCommandError("invalid_claim", "claim must reference a played physical card");
    }
    this.claimChoices.set(seatIndex, cardId);
    if (this.claimChoices.size === this.participants.length - 1) {
      this.resolveClaims();
    }
  }

  public resolveClaimsAtDeadline(): void {
    if (this.participants === null || this.phase !== "claim_commit") {
      throw new MatchCommandError("invalid_phase", "claim commit is not active");
    }
    this.resolveClaims();
  }

  public completeClaimReveal(): void {
    if (this.participants === null || this.phase !== "claim_reveal") {
      throw new MatchCommandError("invalid_phase", "claim reveal is not active");
    }
    if (this.pendingDiscardSeatIndexes.size > 0) {
      this.phase = "award_discard";
      return;
    }
    this.openNextTurn();
  }

  public discardCard(seatIndex: number, cardId: string, turnNumber: number): void {
    if (this.participants === null || this.phase !== "award_discard") {
      throw new MatchCommandError("invalid_phase", "award discard is not active");
    }
    if (!Number.isSafeInteger(turnNumber) || turnNumber !== this.turnNumber) {
      throw new MatchCommandError("stale_turn", "discard does not belong to the current turn");
    }
    if (!this.pendingDiscardSeatIndexes.has(seatIndex)) {
      throw new MatchCommandError(
        "discard_not_required",
        "seat does not have a pending award discard",
      );
    }
    if (typeof cardId !== "string" || cardId.length === 0) {
      throw new MatchCommandError("invalid_discard", "discard requires a card identifier");
    }
    const participant = this.participantAt(seatIndex);
    const card = participant.hand.find((candidate) => candidate.id === cardId);
    if (!card) {
      throw new MatchCommandError("card_not_owned", "card is not owned by the participant");
    }
    if (this.protectedAwardCardIds.get(seatIndex) === card.id) {
      throw new MatchCommandError(
        "awarded_card_protected",
        "the card awarded this turn cannot be discarded",
      );
    }

    this.recordDiscard(participant, card);
    if (this.pendingDiscardSeatIndexes.size === 0) {
      this.openNextTurn();
    }
  }

  public resolveDiscardAtDeadline(): void {
    if (this.participants === null || this.phase !== "award_discard") {
      throw new MatchCommandError("invalid_phase", "award discard is not active");
    }
    const plannedDiscards = [...this.pendingDiscardSeatIndexes].map((seatIndex) => {
      const participant = this.participantAt(seatIndex);
      const protectedCardId = this.protectedAwardCardIds.get(seatIndex);
      const card = participant.hand.find((candidate) => candidate.id !== protectedCardId);
      if (!card) {
        throw new Error("award recipient has no legal card to discard");
      }
      return { participant, card };
    });
    for (const { participant, card } of plannedDiscards) {
      this.recordDiscard(participant, card);
    }
    this.openNextTurn();
  }

  public commitFinalSelection(
    seatIndex: number,
    groups: readonly (readonly string[])[],
  ): void {
    const participant = this.finalCommitParticipant(seatIndex);
    let selection: EvaluatedFinalSelection;
    try {
      selection = evaluateFinalSelection(participant.hand, groups);
    } catch {
      throw new MatchCommandError(
        "invalid_final_selection",
        "final selection must contain two disjoint owned three-card groups",
      );
    }
    this.commitEvaluatedFinalSelection(seatIndex, selection);
  }

  public commitBestFinalSelection(seatIndex: number): void {
    const participant = this.finalCommitParticipant(seatIndex);
    this.commitEvaluatedFinalSelection(
      seatIndex,
      findBestFinalSelection(participant.hand),
    );
  }

  public resolveFinalSelectionsAtDeadline(): void {
    if (this.participants === null || this.phase !== "final_commit") {
      throw new MatchCommandError("invalid_phase", "final selection commit is not active");
    }
    const selections = new Map(this.finalSelections);
    for (const participant of this.participants) {
      if (!selections.has(participant.seatIndex)) {
        selections.set(
          participant.seatIndex,
          findBestFinalSelection(participant.hand),
        );
      }
    }
    this.revealFinalSelections(selections);
  }

  public completeFinalReveal(): void {
    if (this.participants === null || this.phase !== "final_reveal") {
      throw new MatchCommandError("invalid_phase", "final settlement reveal is not active");
    }
    this.phase = "finished";
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
      revealedClaims: Object.freeze([...this.revealedClaims]),
      claimAwards: Object.freeze([...this.claimAwards]),
      discardedCards: Object.freeze([...this.discardedCards]),
      sealedCardCount: this.sealedCards.length,
      pendingDiscardSeatIndexes: Object.freeze([...this.pendingDiscardSeatIndexes]),
      finalResults: Object.freeze([...this.finalResults]),
      winnerSeatIndexes: Object.freeze([...this.winnerSeatIndexes]),
      participants: Object.freeze(publicParticipants),
      events: Object.freeze([...this.events]),
    });
    const privateState: PrivateMatchState = Object.freeze({
      seatIndex: participant.seatIndex,
      participantId: participant.participantId,
      hand: Object.freeze([...participant.hand]),
      claimCommitted: this.claimChoices.has(seatIndex),
      claimCardId: this.claimChoices.get(seatIndex) ?? null,
      finalCommitted: this.finalSelections.has(seatIndex),
      finalGroups: Object.freeze(
        this.finalSelections.get(seatIndex)?.groups.map((group) => (
          Object.freeze(group.cards.map((card) => card.id))
        )) ?? [],
      ),
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

  private resolveClaims(): void {
    if (this.participants === null) {
      throw new Error("cannot resolve claims before the match starts");
    }
    const claims = this.participants
      .filter((participant) => participant.seatIndex !== this.actorSeatIndex)
      .map((participant) => Object.freeze({
        seatIndex: participant.seatIndex,
        cardId: this.claimChoices.get(participant.seatIndex) ?? null,
      }));
    const claimCounts = new Map<string, number>();
    for (const claim of claims) {
      if (claim.cardId !== null) {
        claimCounts.set(claim.cardId, (claimCounts.get(claim.cardId) ?? 0) + 1);
      }
    }
    const awards: ClaimAward[] = [];
    const awardedCardIds = new Set<string>();
    for (const claim of claims) {
      if (claim.cardId === null || claimCounts.get(claim.cardId) !== 1) {
        continue;
      }
      const card = this.playedCards.find((candidate) => candidate.id === claim.cardId);
      if (!card) {
        throw new Error("committed claim does not reference a played card");
      }
      awards.push(Object.freeze({
        seatIndex: claim.seatIndex,
        card,
        source: "unique",
      }));
      awardedCardIds.add(card.id);
    }
    const collisionClaims = claims.filter((claim) => (
      claim.cardId !== null && (claimCounts.get(claim.cardId) ?? 0) > 1
    ));
    const remainingCards = this.playedCards.filter((card) => !awardedCardIds.has(card.id));
    if (collisionClaims.length > 0) {
      this.shuffle(remainingCards);
      for (const claim of collisionClaims) {
        const card = remainingCards.pop();
        if (!card) {
          throw new Error("collision pool cannot satisfy every collision participant");
        }
        awards.push(Object.freeze({
          seatIndex: claim.seatIndex,
          card,
          source: "collision",
        }));
      }
    }
    const discardedCards = remainingCards;
    for (const claim of claims) {
      if (claim.cardId === null) {
        const participant = this.participants.find((candidate) => (
          candidate.seatIndex === claim.seatIndex
        ));
        if (!participant) {
          throw new Error("resolved claim does not belong to a participant");
        }
        participant.score += 1;
      }
    }
    for (const award of awards) {
      const participant = this.participants.find((candidate) => (
        candidate.seatIndex === award.seatIndex
      ));
      if (!participant) {
        throw new Error("claim award does not belong to a participant");
      }
      participant.hand.push(award.card);
    }

    this.revealedClaims = claims;
    this.claimAwards = awards;
    this.pendingDiscardSeatIndexes = new Set(
      awards.map((award) => award.seatIndex).sort((left, right) => left - right),
    );
    this.protectedAwardCardIds = new Map(awards.map((award) => [
      award.seatIndex,
      award.card.id,
    ]));
    this.discardedCards.push(...discardedCards);
    this.playedCards = [];
    this.phase = "claim_reveal";
    this.events.push(Object.freeze({
      type: "claims_resolved",
      turnNumber: this.turnNumber,
      claims: Object.freeze([...claims]),
      awards: Object.freeze([...awards]),
      discardedCards: Object.freeze([...discardedCards]),
    }));
  }

  private participantAt(seatIndex: number): ParticipantState {
    const participant = this.participants?.find((candidate) => (
      candidate.seatIndex === seatIndex
    ));
    if (!participant) {
      throw new MatchCommandError("discard_not_required", "seat does not participate in this match");
    }
    return participant;
  }

  private finalCommitParticipant(seatIndex: number): ParticipantState {
    if (this.participants === null || this.phase !== "final_commit") {
      throw new MatchCommandError("invalid_phase", "final selection commit is not active");
    }
    const participant = this.participants.find((candidate) => candidate.seatIndex === seatIndex);
    if (!participant) {
      throw new MatchCommandError(
        "invalid_final_selection",
        "seat does not participate in final settlement",
      );
    }
    if (this.finalSelections.has(seatIndex)) {
      throw new MatchCommandError(
        "final_selection_already_committed",
        "final selection has already been committed",
      );
    }
    return participant;
  }

  private commitEvaluatedFinalSelection(
    seatIndex: number,
    selection: EvaluatedFinalSelection,
  ): void {
    if (this.participants === null) {
      throw new Error("cannot commit final selection before the match starts");
    }
    const selections = new Map(this.finalSelections);
    selections.set(seatIndex, selection);
    if (selections.size === this.participants.length) {
      this.revealFinalSelections(selections);
    } else {
      this.finalSelections = selections;
    }
  }

  private revealFinalSelections(
    selections: ReadonlyMap<number, EvaluatedFinalSelection>,
  ): void {
    if (this.participants === null || this.phase !== "final_commit") {
      throw new MatchCommandError("invalid_phase", "final selection commit is not active");
    }
    const results = this.participants.map((participant) => {
      const selection = selections.get(participant.seatIndex);
      if (!selection) {
        throw new Error("every participant requires a final selection before reveal");
      }
      return Object.freeze({
        seatIndex: participant.seatIndex,
        groups: selection.groups,
        totalScore: selection.totalScore,
      });
    });
    const finalScores = this.participants.map((participant, index) => (
      participant.score + results[index].totalScore
    ));
    const highestScore = Math.max(...finalScores);
    const winnerSeatIndexes = this.participants
      .filter((_, index) => finalScores[index] === highestScore)
      .map((participant) => participant.seatIndex);
    const event: FinalSettlementEvent = Object.freeze({
      type: "final_settlement",
      results: Object.freeze([...results]),
      winnerSeatIndexes: Object.freeze([...winnerSeatIndexes]),
    });

    this.participants.forEach((participant, index) => {
      participant.score = finalScores[index];
    });
    this.finalSelections = new Map(selections);
    this.finalResults = results;
    this.winnerSeatIndexes = winnerSeatIndexes;
    this.events.push(event);
    this.phase = "final_reveal";
  }

  private recordDiscard(participant: ParticipantState, card: PhysicalCard): void {
    participant.hand = participant.hand.filter((candidate) => candidate.id !== card.id);
    this.pendingDiscardSeatIndexes.delete(participant.seatIndex);
    this.protectedAwardCardIds.delete(participant.seatIndex);
    this.discardedCards.push(card);
    const event: CardDiscardedEvent = Object.freeze({
      type: "card_discarded",
      turnNumber: this.turnNumber,
      seatIndex: participant.seatIndex,
      card,
    });
    this.events.push(event);
  }

  private openNextTurn(): void {
    if (this.participants === null || this.actorSeatIndex === null) {
      throw new Error("cannot open a turn before the match starts");
    }
    if (this.pendingDiscardSeatIndexes.size !== 0) {
      throw new Error("cannot open a turn while award discards are pending");
    }
    if (this.claimAwards.length > 0) {
      this.actorSeatIndex = selectNextActor(this.claimAwards, this.actorSeatIndex);
    }
    for (const participant of this.participants) {
      if (participant.hand.length !== 8) {
        throw new Error("every hand must contain eight cards at a turn boundary");
      }
    }

    this.claimChoices.clear();
    this.revealedClaims = [];
    this.claimAwards = [];
    this.protectedAwardCardIds.clear();
    this.playedCards = [];
    this.playedCategory = null;
    this.playedScore = 0;
    if (this.drawPile.length < 3) {
      this.sealedCards.push(...this.drawPile.splice(0));
      this.actorSeatIndex = -1;
      this.phase = "final_commit";
    } else {
      this.phase = "actor_play";
    }
    this.assertPhysicalCardZones();
  }

  private assertPhysicalCardZones(): void {
    if (this.participants === null) {
      throw new Error("cannot verify card zones before the match starts");
    }
    const cardIds = [
      ...this.participants.flatMap((participant) => participant.hand.map((card) => card.id)),
      ...this.drawPile.map((card) => card.id),
      ...this.discardedCards.map((card) => card.id),
      ...this.sealedCards.map((card) => card.id),
    ];
    if (
      cardIds.length !== this.configuredCardCount
      || new Set(cardIds).size !== this.configuredCardCount
    ) {
      throw new Error("physical cards must occupy exactly one live match zone");
    }
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

function selectNextActor(
  awards: readonly ClaimAward[],
  currentActorSeatIndex: number,
): number {
  if (awards.length === 0) {
    return currentActorSeatIndex;
  }
  let strongestCard = awards[0].card;
  for (const award of awards.slice(1)) {
    if (compareCardStrength(award.card, strongestCard) > 0) {
      strongestCard = award.card;
    }
  }
  const strongestAwards = awards.filter((award) => (
    compareCardStrength(award.card, strongestCard) === 0
  ));
  return [...strongestAwards].sort((left, right) => (
    clockwiseDistance(currentActorSeatIndex, left.seatIndex)
    - clockwiseDistance(currentActorSeatIndex, right.seatIndex)
  ))[0].seatIndex;
}

function clockwiseDistance(fromSeatIndex: number, toSeatIndex: number): number {
  const distance = (toSeatIndex - fromSeatIndex + REQUIRED_SEAT_INDICES.length)
    % REQUIRED_SEAT_INDICES.length;
  return distance === 0 ? REQUIRED_SEAT_INDICES.length : distance;
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
