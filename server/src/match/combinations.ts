import type { PhysicalCard } from "./cards.js";

export type CombinationCategory =
  | "high_card"
  | "pair"
  | "flush"
  | "straight"
  | "three_of_a_kind"
  | "straight_flush";

export interface ScoredCombination {
  readonly category: CombinationCategory;
  readonly score: number;
}

export function classifyCombination(
  cards: readonly PhysicalCard[],
): ScoredCombination {
  if (!Array.isArray(cards) || cards.length !== 3) {
    throw new Error("a combination requires exactly three cards");
  }
  const rankCount = new Set(cards.map((card) => card.rank)).size;
  const isFlush = new Set(cards.map((card) => card.suit)).size === 1;
  const sortedRanks = cards.map((card) => card.rank).sort((left, right) => left - right);
  const isStraight = (
    (
      sortedRanks[1] === sortedRanks[0] + 1
      && sortedRanks[2] === sortedRanks[1] + 1
    )
    || sortedRanks.join(",") === "2,3,14"
  );

  if (isStraight && isFlush) {
    return Object.freeze({ category: "straight_flush", score: 10 });
  }
  if (rankCount === 1) {
    return Object.freeze({ category: "three_of_a_kind", score: 8 });
  }
  if (isStraight) {
    return Object.freeze({ category: "straight", score: 5 });
  }
  if (isFlush) {
    return Object.freeze({ category: "flush", score: 4 });
  }
  if (rankCount === 2) {
    return Object.freeze({ category: "pair", score: 2 });
  }
  return Object.freeze({ category: "high_card", score: 0 });
}
