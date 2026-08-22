export const CARD_RANKS = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14] as const;
export type CardRank = (typeof CARD_RANKS)[number];

export const CARD_SUITS = ["clubs", "spades", "diamonds", "hearts"] as const;
export type CardSuit = (typeof CARD_SUITS)[number];

export const DECK_MODES = ["one", "two"] as const;
export type DeckMode = (typeof DECK_MODES)[number];

export interface PhysicalCard {
  readonly id: string;
  readonly rank: CardRank;
  readonly suit: CardSuit;
  readonly copyIndex: number;
}

const SUIT_STRENGTH = new Map(CARD_SUITS.map((suit, index) => [suit, index]));

/**
 * Compares gameplay strength only. Physical copies of the same rank and suit
 * intentionally tie so two-deck point contests keep their redraw semantics.
 */
export function compareCardStrength(left: PhysicalCard, right: PhysicalCard): number {
  return (
    left.rank - right.rank
    || (SUIT_STRENGTH.get(left.suit) ?? -1) - (SUIT_STRENGTH.get(right.suit) ?? -1)
  );
}

/**
 * Compares cards for deterministic selection. Copy and id are stable fallbacks
 * only; they do not contribute to gameplay strength or scoring.
 */
export function compareCardPreference(left: PhysicalCard, right: PhysicalCard): number {
  return (
    compareCardStrength(left, right)
    || right.copyIndex - left.copyIndex
    || -compareStrings(left.id, right.id)
  );
}

export function compareCardsStrongestFirst(left: PhysicalCard, right: PhysicalCard): number {
  return -compareCardPreference(left, right);
}

export function createPhysicalDeck(deckMode: DeckMode): readonly PhysicalCard[] {
  if (deckMode !== "one" && deckMode !== "two") {
    throw new Error("deckMode must be one or two");
  }

  const copyCount = deckMode === "one" ? 1 : 2;
  const cards: PhysicalCard[] = [];
  for (let copyIndex = 0; copyIndex < copyCount; copyIndex += 1) {
    for (const suit of CARD_SUITS) {
      for (const rank of CARD_RANKS) {
        cards.push(Object.freeze({
          id: `copy-${copyIndex}:${suit}:${rank}`,
          rank,
          suit,
          copyIndex,
        }));
      }
    }
  }
  return Object.freeze(cards);
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
