import {
  compareCardPreference,
  compareCardsStrongestFirst,
  type PhysicalCard,
} from "./cards.js";
import { combinationsOfThree } from "./combinatorics.js";
import {
  classifyCombination,
  type CombinationCategory,
} from "./combinations.js";

export interface FinalCombination {
  readonly cards: readonly PhysicalCard[];
  readonly category: CombinationCategory;
  readonly score: number;
}

export interface EvaluatedFinalSelection {
  readonly groups: readonly FinalCombination[];
  readonly unusedCards: readonly PhysicalCard[];
  readonly totalScore: number;
}

export function evaluateFinalSelection(
  hand: readonly PhysicalCard[],
  selectedCardIds: readonly string[],
): EvaluatedFinalSelection {
  const handById = validateHand(hand);
  if (
    !Array.isArray(selectedCardIds)
    || selectedCardIds.length !== 3
    || !Array.from(selectedCardIds as readonly unknown[]).every((cardId) => (
      typeof cardId === "string" && cardId.length > 0
    ))
  ) {
    throw new Error("a final selection requires three physical card identifiers");
  }
  const selectedIds = Array.from(selectedCardIds);
  if (new Set(selectedIds).size !== 3) {
    throw new Error("a final selection requires three distinct physical cards");
  }
  if (!selectedIds.every((cardId) => handById.has(cardId))) {
    throw new Error("final selection cards must belong to the participant hand");
  }

  const cards = selectedIds
    .map((cardId) => handById.get(cardId)!)
    .sort(compareCardsStrongestFirst);
  const classification = classifyCombination(cards);
  const group: FinalCombination = Object.freeze({
    cards: Object.freeze(cards),
    category: classification.category,
    score: classification.score,
  });
  const selectedIdSet = new Set(selectedIds);
  const unusedCards = [...hand]
    .filter((card) => !selectedIdSet.has(card.id))
    .sort(compareCardsStrongestFirst);

  return Object.freeze({
    groups: Object.freeze([group]),
    unusedCards: Object.freeze(unusedCards),
    totalScore: group.score,
  });
}

export function findBestFinalSelection(
  hand: readonly PhysicalCard[],
): EvaluatedFinalSelection {
  validateHand(hand);
  const sortedCards = [...hand].sort(compareCardsStrongestFirst);
  const candidates = combinationsOfThree(sortedCards.map((card) => card.id));
  let best: EvaluatedFinalSelection | null = null;

  for (const candidateIds of candidates) {
    const candidate = evaluateFinalSelection(sortedCards, candidateIds);
    if (
      best === null
      || candidate.totalScore > best.totalScore
      || (
        candidate.totalScore === best.totalScore
        && compareSelections(candidate, best) > 0
      )
    ) {
      best = candidate;
    }
  }

  if (best === null) {
    throw new Error("a five-card hand must have a legal final selection");
  }
  return best;
}

function validateHand(hand: readonly PhysicalCard[]): Map<string, PhysicalCard> {
  if (!Array.isArray(hand) || hand.length !== 5) {
    throw new Error("final settlement requires a five-card hand");
  }
  const cards = Array.from(hand);
  if (!cards.every((card) => (
    typeof card === "object"
    && card !== null
    && typeof card.id === "string"
    && card.id.length > 0
  ))) {
    throw new Error("final settlement hand contains an invalid physical card");
  }
  const handById = new Map(cards.map((card) => [card.id, card]));
  if (handById.size !== cards.length) {
    throw new Error("final settlement hand must contain unique physical cards");
  }
  return handById;
}

function compareSelections(
  left: EvaluatedFinalSelection,
  right: EvaluatedFinalSelection,
): number {
  const leftCards = left.groups[0].cards;
  const rightCards = right.groups[0].cards;
  for (let index = 0; index < leftCards.length; index += 1) {
    const comparison = compareCardPreference(leftCards[index], rightCards[index]);
    if (comparison !== 0) {
      return comparison;
    }
  }
  return 0;
}
