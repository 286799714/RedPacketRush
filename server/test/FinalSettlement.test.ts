import assert from "assert";

import type { CardRank, CardSuit, PhysicalCard } from "../src/match/cards.js";
import {
  evaluateFinalSelection,
  findBestFinalSelection,
} from "../src/match/finalSettlement.js";

function card(
  id: string,
  rank: CardRank,
  suit: CardSuit,
  copyIndex = 0,
): PhysicalCard {
  return Object.freeze({ id, rank, suit, copyIndex });
}

describe("final settlement rules", () => {
  it("evaluates one three-card combination from a five-card hand", () => {
    const hand = [
      card("straight-2", 2, "clubs"),
      card("straight-3", 3, "diamonds"),
      card("straight-4", 4, "hearts"),
      card("unused-jack", 11, "clubs"),
      card("unused-ace", 14, "hearts"),
    ] as const;

    const selection = evaluateFinalSelection(hand, [
      "straight-3",
      "straight-2",
      "straight-4",
    ]);

    assert.deepStrictEqual(selection.groups.map((group) => ({
      ids: group.cards.map((selectedCard) => selectedCard.id),
      category: group.category,
      score: group.score,
    })), [{
      ids: ["straight-4", "straight-3", "straight-2"],
      category: "straight",
      score: 5,
    }]);
    assert.strictEqual(selection.totalScore, 5);
    assert.deepStrictEqual(
      selection.unusedCards.map((unusedCard) => unusedCard.id),
      ["unused-ace", "unused-jack"],
    );
  });

  it("rejects malformed, unowned, duplicate, and non-five-card selections", () => {
    const hand = [
      card("a", 2, "clubs"),
      card("b", 3, "clubs"),
      card("c", 4, "clubs"),
      card("d", 5, "spades"),
      card("e", 6, "spades"),
    ] as const;
    const invalidSelections: unknown[] = [
      null,
      ["a", "b"],
      ["a", "b", 42],
      ["a", "b", "b"],
      ["a", "b", "missing"],
    ];

    for (const selection of invalidSelections) {
      assert.throws(
        () => evaluateFinalSelection(hand, selection as readonly string[]),
        Error,
      );
    }
    assert.throws(
      () => evaluateFinalSelection([...hand.slice(0, 4), hand[0]], ["a", "b", "c"]),
      /unique physical cards/,
    );
    assert.throws(
      () => evaluateFinalSelection(hand.slice(0, 4), ["a", "b", "c"]),
      /five-card hand/,
    );
  });

  it("selects the highest-scoring combination from all ten subsets", () => {
    const hand = [
      card("seven-clubs", 7, "clubs"),
      card("seven-spades", 7, "spades"),
      card("seven-hearts", 7, "hearts"),
      card("eight-diamonds", 8, "diamonds"),
      card("nine-clubs", 9, "clubs"),
    ] as const;

    const best = findBestFinalSelection(hand);

    assert.strictEqual(best.totalScore, 8);
    assert.deepStrictEqual(best.groups.map((group) => ({
      ids: group.cards.map((selectedCard) => selectedCard.id),
      category: group.category,
      score: group.score,
    })), [{
      ids: ["seven-hearts", "seven-spades", "seven-clubs"],
      category: "three_of_a_kind",
      score: 8,
    }]);
  });

  it("breaks equal scores by rank then hearts, diamonds, spades, clubs", () => {
    const tiedHand = [
      card("seven-hearts", 7, "hearts"),
      card("seven-diamonds", 7, "diamonds"),
      card("seven-spades", 7, "spades"),
      card("seven-clubs", 7, "clubs"),
      card("two-hearts", 2, "hearts"),
    ] as const;

    const forward = findBestFinalSelection(tiedHand);
    const reversed = findBestFinalSelection([...tiedHand].reverse());

    assert.strictEqual(forward.totalScore, 8);
    assert.deepStrictEqual(
      forward.groups[0].cards.map((selectedCard) => selectedCard.id),
      ["seven-hearts", "seven-diamonds", "seven-spades"],
    );
    assert.deepStrictEqual(reversed, forward);
    assert.deepStrictEqual(
      forward.unusedCards.map((unusedCard) => unusedCard.id),
      ["seven-clubs", "two-hearts"],
    );
  });

  it("uses copy and id only as stable fallbacks for duplicate physical cards", () => {
    const hand = [
      card("hearts-copy-1", 7, "hearts", 1),
      card("z-hearts-copy-0", 7, "hearts"),
      card("a-hearts-copy-0", 7, "hearts"),
      card("diamonds-copy-0", 7, "diamonds"),
      card("spades-copy-0", 7, "spades"),
    ] as const;

    const best = findBestFinalSelection(hand);

    assert.deepStrictEqual(
      best.groups[0].cards.map((selectedCard) => selectedCard.id),
      ["a-hearts-copy-0", "z-hearts-copy-0", "hearts-copy-1"],
    );
    assert.deepStrictEqual(
      best.unusedCards.map((unusedCard) => unusedCard.id),
      ["diamonds-copy-0", "spades-copy-0"],
    );
  });
});
