import type { MatchView } from "./MatchEngine.js";

export type BotCommand =
  | { readonly type: "play_cards"; readonly cardIds: readonly string[] }
  | { readonly type: "claim"; readonly cardId: string | null }
  | { readonly type: "discard"; readonly cardId: string; readonly turnNumber: number }
  | { readonly type: "final_selection"; readonly mode: "best" };

export function chooseBotCommand(view: MatchView): BotCommand | null {
  const { publicState, privateState } = view;
  const seatIndex = privateState.seatIndex;

  if (publicState.phase === "actor_play") {
    if (publicState.actorSeatIndex !== seatIndex || privateState.hand.length < 3) {
      return null;
    }
    return {
      type: "play_cards",
      cardIds: privateState.hand.slice(0, 3).map((card) => card.id),
    };
  }

  if (publicState.phase === "claim_commit") {
    if (publicState.actorSeatIndex === seatIndex || privateState.claimCommitted) {
      return null;
    }
    const [playedCard] = publicState.playedCards;
    if (!playedCard) {
      return null;
    }
    return {
      type: "claim",
      cardId: playedCard.id,
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
      cardId: discardableCards[0].id,
      turnNumber: publicState.turnNumber,
    };
  }

  if (publicState.phase === "final_commit" && !privateState.finalCommitted) {
    return { type: "final_selection", mode: "best" };
  }

  return null;
}
