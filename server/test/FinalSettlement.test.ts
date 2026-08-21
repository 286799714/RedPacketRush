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
  it("evaluates two disjoint combinations and reports the unused physical cards", () => {
    const hand = [
      card("straight-2", 2, "clubs"),
      card("straight-3", 3, "diamonds"),
      card("straight-4", 4, "hearts"),
      card("triple-a", 9, "clubs"),
      card("triple-b", 9, "spades"),
      card("triple-c", 9, "hearts"),
      card("unused-a", 11, "clubs"),
      card("unused-b", 14, "hearts"),
    ] as const;

    const selection = evaluateFinalSelection(hand, [
      ["triple-c", "triple-a", "triple-b"],
      ["straight-4", "straight-2", "straight-3"],
    ]);

    assert.deepStrictEqual(selection.groups.map((group) => ({
      ids: group.cards.map((selectedCard) => selectedCard.id),
      category: group.category,
      score: group.score,
    })), [
      { ids: ["straight-2", "straight-3", "straight-4"], category: "straight", score: 5 },
      { ids: ["triple-a", "triple-b", "triple-c"], category: "three_of_a_kind", score: 8 },
    ]);
    assert.strictEqual(selection.totalScore, 13);
    assert.deepStrictEqual(
      selection.unusedCards.map((unusedCard) => unusedCard.id),
      ["unused-a", "unused-b"],
    );
  });

  it("rejects malformed, overlapping, unowned, and duplicate physical selections", () => {
    const hand = [
      card("a", 2, "clubs"),
      card("b", 3, "clubs"),
      card("c", 4, "clubs"),
      card("d", 5, "spades"),
      card("e", 6, "spades"),
      card("f", 7, "spades"),
      card("g", 8, "diamonds"),
      card("h", 9, "hearts"),
    ] as const;
    const invalidGroups: unknown[] = [
      null,
      [["a", "b", "c"]],
      [["a", "b", "c"], ["d", "e"]],
      [["a", "b", "c"], ["d", "e", 42]],
      [["a", "b", "c"], ["c", "d", "e"]],
      [["a", "b", "c"], ["d", "e", "missing"]],
    ];

    for (const groups of invalidGroups) {
      assert.throws(
        () => evaluateFinalSelection(hand, groups as readonly (readonly string[])[]),
        Error,
      );
    }
    assert.throws(
      () => evaluateFinalSelection([...hand.slice(0, 7), hand[0]], [
        ["a", "b", "c"],
        ["d", "e", "f"],
      ]),
      /unique physical cards/,
    );
  });

  it("finds the maximum total and resolves equal optima by canonical physical ids", () => {
    const tiedHand = [
      card("h", 7, "hearts", 1),
      card("g", 7, "diamonds", 1),
      card("f", 7, "spades", 1),
      card("e", 7, "clubs", 1),
      card("d", 7, "hearts"),
      card("c", 7, "diamonds"),
      card("b", 7, "spades"),
      card("a", 7, "clubs"),
    ] as const;

    const forward = findBestFinalSelection(tiedHand);
    const reversed = findBestFinalSelection([...tiedHand].reverse());

    assert.strictEqual(forward.totalScore, 16);
    assert.deepStrictEqual(
      forward.groups.map((group) => group.cards.map((selectedCard) => selectedCard.id)),
      [["a", "b", "c"], ["d", "e", "f"]],
    );
    assert.deepStrictEqual(reversed, forward);
    assert.deepStrictEqual(
      forward.unusedCards.map((unusedCard) => unusedCard.id),
      ["g", "h"],
    );
  });
});
