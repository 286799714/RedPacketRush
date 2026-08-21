import type { MatchView } from "./MatchEngine.js";
import type { RandomSource } from "./random.js";

export type BotCommand =
  | { readonly type: "play_cards"; readonly cardIds: readonly string[] }
  | { readonly type: "claim"; readonly cardId: string | null }
  | { readonly type: "discard"; readonly cardId: string; readonly turnNumber: number }
  | { readonly type: "final_selection"; readonly mode: "best" };

export function chooseBotCommand(view: MatchView, random: RandomSource): BotCommand | null {
  const { publicState, privateState } = view;
  const seatIndex = privateState.seatIndex;

  if (publicState.phase === "actor_play") {
    if (publicState.actorSeatIndex !== seatIndex || privateState.hand.length < 3) {
      return null;
    }
    const combinations = chooseThree(privateState.hand.map((card) => card.id));
    return {
      type: "play_cards",
      cardIds: combinations[randomIndex(random, combinations.length)],
    };
  }

  if (publicState.phase === "claim_commit") {
    if (publicState.actorSeatIndex === seatIndex || privateState.claimCommitted) {
      return null;
    }
    const choices = [...publicState.playedCards.map((card) => card.id), null];
    return {
      type: "claim",
      cardId: choices[randomIndex(random, choices.length)],
    };
  }

  if (publicState.phase === "award_discard") {
    if (!publicState.pendingDiscardSeatIndexes.includes(seatIndex)) {
      return null;
    }
    const protectedCardId = publicState.claimAwards.find(
      (award) => award.seatIndex === seatIndex,
    )?.card.id;
    const discardableCards = privateState.hand.filter((card) => card.id !== protectedCardId);
    if (discardableCards.length === 0) {
      return null;
    }
    return {
      type: "discard",
      cardId: discardableCards[randomIndex(random, discardableCards.length)].id,
      turnNumber: publicState.turnNumber,
    };
  }

  if (publicState.phase === "final_commit" && !privateState.finalCommitted) {
    return { type: "final_selection", mode: "best" };
  }

  return null;
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
