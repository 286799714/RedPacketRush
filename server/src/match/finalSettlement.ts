import { CARD_SUITS, type PhysicalCard } from "./cards.js";
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

const SUIT_ORDER = new Map(CARD_SUITS.map((suit, index) => [suit, index]));

export function evaluateFinalSelection(
  hand: readonly PhysicalCard[],
  groups: readonly (readonly string[])[],
): EvaluatedFinalSelection {
  const handById = validateHand(hand);
  if (!Array.isArray(groups) || groups.length !== 2) {
    throw new Error("a final selection requires exactly two groups");
  }
  if (!Array.from(groups as readonly unknown[]).every((group) => (
    Array.isArray(group)
    && group.length === 3
    && Array.from(group).every((cardId) => typeof cardId === "string" && cardId.length > 0)
  ))) {
    throw new Error("each final selection group requires three physical card identifiers");
  }
  const submittedGroups: string[][] = Array.from(
    groups as readonly (readonly string[])[],
    (group) => Array.from(group),
  );
  const selectedIds = submittedGroups.flatMap((group) => Array.from(group));
  if (new Set(selectedIds).size !== 6) {
    throw new Error("final selection groups must be disjoint physical cards");
  }
  if (!selectedIds.every((cardId) => handById.has(cardId))) {
    throw new Error("final selection cards must belong to the participant hand");
  }

  const canonicalGroups = submittedGroups
    .map((group) => group
      .map((cardId) => handById.get(cardId)!)
      .sort(comparePhysicalCards))
    .sort(comparePhysicalCardArrays);
  const evaluatedGroups = canonicalGroups.map((cards) => {
    const classification = classifyCombination(cards);
    return Object.freeze({
      cards: Object.freeze(cards),
      category: classification.category,
      score: classification.score,
    });
  });
  const selectedIdSet = new Set(selectedIds);
  const unusedCards = [...hand]
    .filter((card) => !selectedIdSet.has(card.id))
    .sort(comparePhysicalCards);

  return Object.freeze({
    groups: Object.freeze(evaluatedGroups),
    unusedCards: Object.freeze(unusedCards),
    totalScore: evaluatedGroups.reduce((score, group) => score + group.score, 0),
  });
}

export function findBestFinalSelection(
  hand: readonly PhysicalCard[],
): EvaluatedFinalSelection {
  validateHand(hand);
  const sortedCards = [...hand].sort(comparePhysicalCards);
  const groupCandidates = chooseThree(sortedCards.map((card) => card.id));
  let best: EvaluatedFinalSelection | null = null;

  for (let firstIndex = 0; firstIndex < groupCandidates.length; firstIndex += 1) {
    const firstGroup = groupCandidates[firstIndex];
    const firstIds = new Set(firstGroup);
    for (let secondIndex = firstIndex + 1; secondIndex < groupCandidates.length; secondIndex += 1) {
      const secondGroup = groupCandidates[secondIndex];
      if (secondGroup.some((cardId) => firstIds.has(cardId))) {
        continue;
      }
      const candidate = evaluateFinalSelection(sortedCards, [firstGroup, secondGroup]);
      if (
        best === null
        || candidate.totalScore > best.totalScore
        || (
          candidate.totalScore === best.totalScore
          && compareSelections(candidate, best) < 0
        )
      ) {
        best = candidate;
      }
    }
  }

  if (best === null) {
    throw new Error("an eight-card hand must have a legal final selection");
  }
  return best;
}

function validateHand(hand: readonly PhysicalCard[]): Map<string, PhysicalCard> {
  if (!Array.isArray(hand) || hand.length !== 8) {
    throw new Error("final settlement requires an eight-card hand");
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

function chooseThree(cardIds: readonly string[]): string[][] {
  const groups: string[][] = [];
  for (let first = 0; first < cardIds.length - 2; first += 1) {
    for (let second = first + 1; second < cardIds.length - 1; second += 1) {
      for (let third = second + 1; third < cardIds.length; third += 1) {
        groups.push([cardIds[first], cardIds[second], cardIds[third]]);
      }
    }
  }
  return groups;
}

function compareSelections(
  left: EvaluatedFinalSelection,
  right: EvaluatedFinalSelection,
): number {
  const leftGroups = left.groups.map((group) => group.cards);
  const rightGroups = right.groups.map((group) => group.cards);
  for (let index = 0; index < leftGroups.length; index += 1) {
    const comparison = comparePhysicalCardArrays(leftGroups[index], rightGroups[index]);
    if (comparison !== 0) {
      return comparison;
    }
  }
  return 0;
}

function comparePhysicalCardArrays(
  left: readonly PhysicalCard[],
  right: readonly PhysicalCard[],
): number {
  for (let index = 0; index < Math.min(left.length, right.length); index += 1) {
    const comparison = comparePhysicalCards(left[index], right[index]);
    if (comparison !== 0) {
      return comparison;
    }
  }
  return left.length - right.length;
}

function comparePhysicalCards(left: PhysicalCard, right: PhysicalCard): number {
  return (
    left.rank - right.rank
    || (SUIT_ORDER.get(left.suit) ?? -1) - (SUIT_ORDER.get(right.suit) ?? -1)
    || left.copyIndex - right.copyIndex
    || compareStrings(left.id, right.id)
  );
}

function compareStrings(left: string, right: string): number {
  if (left < right) {
    return -1;
  }
  if (left > right) {
    return 1;
  }
  return 0;
}
