import type { MatchView } from "./MatchEngine.js";
import type { RandomSource } from "./random.js";

export type BotCommand =
  | { readonly type: "play_cards"; readonly cardIds: readonly string[] }
  | { readonly type: "claim"; readonly cardId: string | null }
  | { readonly type: "discard"; readonly cardId: string; readonly turnNumber: number }
  | { readonly type: "final_selection"; readonly mode: "best" };

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
  if (publicState.phase === "final_commit" && !privateState.finalCommitted) {
    return "final_selection";
  }
  return null;
}

export function chooseBotCommand(view: MatchView, random: RandomSource): BotCommand | null {
  const { publicState, privateState } = view;
  const commandType = eligibleBotCommandType(view);

  if (commandType === "play_cards") {
    const combinations = chooseThree(privateState.hand.map((card) => card.id));
    return {
      type: "play_cards",
      cardIds: combinations[randomIndex(random, combinations.length)],
    };
  }

  if (commandType === "claim") {
    const choices = [...publicState.playedCards.map((card) => card.id), null];
    return {
      type: "claim",
      cardId: choices[randomIndex(random, choices.length)],
    };
  }

  if (commandType === "discard") {
    const discardableCards = discardableBotCards(view);
    return {
      type: "discard",
      cardId: discardableCards[randomIndex(random, discardableCards.length)].id,
      turnNumber: publicState.turnNumber,
    };
  }

  if (commandType === "final_selection") {
    return { type: "final_selection", mode: "best" };
  }

  return null;
}

function discardableBotCards(view: MatchView) {
  const { publicState, privateState } = view;
  if (!publicState.pendingDiscardSeatIndexes.includes(privateState.seatIndex)) {
    return [];
  }
  const protectedCardId = publicState.claimAwards.find(
    (award) => award.seatIndex === privateState.seatIndex,
  )?.card.id;
  return privateState.hand.filter((card) => card.id !== protectedCardId);
}

function chooseThree(cardIds: readonly string[]): string[][] {
  const combinations: string[][] = [];
  for (let first = 0; first < cardIds.length - 2; first += 1) {
    for (let second = first + 1; second < cardIds.length - 1; second += 1) {
      for (let third = second + 1; third < cardIds.length; third += 1) {
        combinations.push([cardIds[first], cardIds[second], cardIds[third]]);
      }
    }
  }
  return combinations;
}

function randomIndex(random: RandomSource, maxExclusive: number): number {
  const index = random.nextInt(maxExclusive);
  if (!Number.isSafeInteger(index) || index < 0 || index >= maxExclusive) {
    throw new Error(`random source returned invalid index ${index} for ${maxExclusive}`);
  }
  return index;
}
