import type { MatchView } from "./MatchEngine.js";
import { compareCardPreference, type PhysicalCard } from "./cards.js";
import { findBestFinalSelection } from "./finalSettlement.js";

export const BOT_STRATEGIES = ["conservative", "aggressive"] as const;
export type BotStrategy = (typeof BOT_STRATEGIES)[number];

export type BotCommand =
  | { readonly type: "play_cards"; readonly cardIds: readonly string[] }
  | { readonly type: "claim"; readonly cardId: string | null }
  | { readonly type: "discard"; readonly cardId: string; readonly turnNumber: number };

export function chooseAutomaticPlayCardIds(view: MatchView): readonly string[] | null {
  const { publicState, privateState } = view;
  if (
    publicState.phase !== "actor_play"
    || publicState.actorSeatIndex !== privateState.seatIndex
    || privateState.hand.length < 3
  ) {
    return null;
  }
  return privateState.hand.slice(0, 3).map((card) => card.id);
}

export function eligibleBotCommandType(view: MatchView): BotCommand["type"] | null {
  const { publicState, privateState } = view;
  const seatIndex = privateState.seatIndex;

  if (chooseAutomaticPlayCardIds(view) !== null) {
    return "play_cards";
  }
  if (
    publicState.phase === "claim_commit"
    && publicState.actorSeatIndex !== seatIndex
    && !privateState.claimCommitted
    && publicState.playedCards.length > 0
  ) {
    return "claim";
  }
  if (publicState.phase === "award_discard" && discardableBotCards(view).length > 0) {
    return "discard";
  }
  return null;
}

export function chooseBotCommand(
  view: MatchView,
  strategy: BotStrategy,
): BotCommand | null {
  const { publicState, privateState } = view;
  const commandType = eligibleBotCommandType(view);

  if (commandType === "play_cards") {
    return {
      type: "play_cards",
      cardIds: findBestFinalSelection(privateState.hand).groups[0].cards.map((card) => card.id),
    };
  }

  if (commandType === "claim" && strategy === "aggressive") {
    const strongestCard = publicState.playedCards.reduce((strongest, card) => (
      compareCardPreference(card, strongest) > 0 ? card : strongest
    ));
    return { type: "claim", cardId: strongestCard.id };
  }
  if (commandType === "claim" && strategy === "conservative") {
    if (findBestFinalSelection(privateState.hand).totalScore > 2) {
      const strongestCard = publicState.playedCards.reduce((strongest, card) => (
        compareCardPreference(card, strongest) > 0 ? card : strongest
      ));
      return { type: "claim", cardId: strongestCard.id };
    }
    const improvingCards = publicState.playedCards
      .map((card) => ({ card, improvement: improvementFrom(card, privateState.hand) }))
      .filter(({ improvement }) => improvement.some((count) => count > 0));
    if (improvingCards.length === 0) {
      return { type: "claim", cardId: null };
    }
    const best = improvingCards.reduce((currentBest, candidate) => (
      compareImprovements(candidate, currentBest) > 0 ? candidate : currentBest
    ));
    return { type: "claim", cardId: best.card.id };
  }
  if (commandType === "discard") {
    const [cardToDiscard] = [...discardableBotCards(view)].sort((left, right) => (
      discardPriority(left, privateState.hand) - discardPriority(right, privateState.hand)
      || compareCardPreference(left, right)
    ));
    return {
      type: "discard",
      cardId: cardToDiscard.id,
      turnNumber: publicState.turnNumber,
    };
  }

  return null;
}

function improvementFrom(
  card: PhysicalCard,
  hand: readonly PhysicalCard[],
): readonly [number, number, number] {
  return [
    hand.filter((heldCard) => heldCard.rank === card.rank).length,
    hand.filter((heldCard) => heldCard.suit === card.suit).length,
    hand.filter((heldCard) => ranksAreAdjacent(heldCard.rank, card.rank)).length,
  ];
}

function compareImprovements(
  left: { readonly card: PhysicalCard; readonly improvement: readonly number[] },
  right: { readonly card: PhysicalCard; readonly improvement: readonly number[] },
): number {
  for (let index = 0; index < left.improvement.length; index += 1) {
    const difference = left.improvement[index] - right.improvement[index];
    if (difference !== 0) {
      return difference;
    }
  }
  return compareCardPreference(left.card, right.card);
}

function ranksAreAdjacent(left: PhysicalCard["rank"], right: PhysicalCard["rank"]): boolean {
  return Math.abs(left - right) === 1 || (
    (left === 2 && right === 14) || (left === 14 && right === 2)
  );
}

function discardPriority(card: PhysicalCard, hand: readonly PhysicalCard[]): number {
  const otherCards = hand.filter((otherCard) => otherCard.id !== card.id);
  if (otherCards.some((otherCard) => otherCard.rank === card.rank)) {
    return 4;
  }
  const hasSameSuit = otherCards.some((otherCard) => otherCard.suit === card.suit);
  const hasAdjacentRank = otherCards.some((otherCard) => (
    ranksAreAdjacent(otherCard.rank, card.rank)
  ));
  if (hasSameSuit && hasAdjacentRank) {
    return 3;
  }
  if (hasSameSuit) {
    return 2;
  }
  if (hasAdjacentRank) {
    return 1;
  }
  return 0;
}

function discardableBotCards(view: MatchView) {
  const { publicState, privateState } = view;
  if (!publicState.pendingDiscardSeatIndexes.includes(privateState.seatIndex)) {
    return [];
  }
  return privateState.hand;
}
