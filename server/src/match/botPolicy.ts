import type { MatchView } from "./MatchEngine.js";
import { combinationsOfThree } from "./combinatorics.js";
import { nextRandomIndex, type RandomSource } from "./random.js";

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

export function chooseBotCommand(view: MatchView, random: RandomSource): BotCommand | null {
  const { publicState, privateState } = view;
  const commandType = eligibleBotCommandType(view);

  if (commandType === "play_cards") {
    const combinations = combinationsOfThree(privateState.hand.map((card) => card.id));
    return {
      type: "play_cards",
      cardIds: combinations[nextRandomIndex(random, combinations.length)],
    };
  }

  if (commandType === "claim") {
    const choices = [...publicState.playedCards.map((card) => card.id), null];
    return {
      type: "claim",
      cardId: choices[nextRandomIndex(random, choices.length)],
    };
  }

  if (commandType === "discard") {
    const discardableCards = discardableBotCards(view);
    return {
      type: "discard",
      cardId: discardableCards[nextRandomIndex(random, discardableCards.length)].id,
      turnNumber: publicState.turnNumber,
    };
  }

  return null;
}

function discardableBotCards(view: MatchView) {
  const { publicState, privateState } = view;
  if (!publicState.pendingDiscardSeatIndexes.includes(privateState.seatIndex)) {
    return [];
  }
  return privateState.hand;
}
