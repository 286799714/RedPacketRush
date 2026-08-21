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
