import assert from "assert";

import { createPhysicalDeck, type PhysicalCard } from "../src/match/cards.js";
import { classifyCombination } from "../src/match/combinations.js";

const TWO_DECKS = createPhysicalDeck("two");

function cards(...ids: string[]): PhysicalCard[] {
  return ids.map((id) => {
    const card = TWO_DECKS.find((candidate) => candidate.id === id);
    assert.ok(card, `missing test card ${id}`);
    return card;
  });
}

describe("three-card combination scoring", () => {
  it("scores a high-card combination as zero", () => {
    assert.deepStrictEqual(classifyCombination(cards(
      "copy-0:clubs:2",
      "copy-0:spades:6",
      "copy-0:hearts:11",
    )), {
      category: "high_card",
      score: 0,
    });
  });

  it("scores one pair as two", () => {
    assert.deepStrictEqual(classifyCombination(cards(
      "copy-0:clubs:9",
      "copy-0:spades:9",
      "copy-0:hearts:4",
    )), {
      category: "pair",
      score: 2,
    });
  });

  it("scores a flush as four", () => {
    assert.deepStrictEqual(classifyCombination(cards(
      "copy-0:diamonds:2",
      "copy-0:diamonds:7",
      "copy-0:diamonds:12",
    )), {
      category: "flush",
      score: 4,
    });
  });

  it("scores a straight as five", () => {
    assert.deepStrictEqual(classifyCombination(cards(
      "copy-0:clubs:6",
      "copy-0:diamonds:7",
      "copy-0:spades:8",
    )), {
      category: "straight",
      score: 5,
    });
  });

  it("treats ace-two-three as a straight", () => {
    assert.deepStrictEqual(classifyCombination(cards(
      "copy-0:hearts:14",
      "copy-0:clubs:2",
      "copy-0:spades:3",
    )), {
      category: "straight",
      score: 5,
    });
  });

  it("treats queen-king-ace as a straight", () => {
    assert.deepStrictEqual(classifyCombination(cards(
      "copy-0:spades:12",
      "copy-0:diamonds:13",
      "copy-0:clubs:14",
    )), {
      category: "straight",
      score: 5,
    });
  });

  it("does not treat king-ace-two as a straight", () => {
    assert.deepStrictEqual(classifyCombination(cards(
      "copy-0:clubs:13",
      "copy-0:diamonds:14",
      "copy-0:spades:2",
    )), {
      category: "high_card",
      score: 0,
    });
  });

  it("scores three of a kind as eight", () => {
    assert.deepStrictEqual(classifyCombination(cards(
      "copy-0:clubs:10",
      "copy-0:diamonds:10",
      "copy-0:hearts:10",
    )), {
      category: "three_of_a_kind",
      score: 8,
    });
  });

  it("scores a straight flush as ten", () => {
    assert.deepStrictEqual(classifyCombination(cards(
      "copy-0:spades:10",
      "copy-0:spades:11",
      "copy-0:spades:12",
    )), {
      category: "straight_flush",
      score: 10,
    });
  });

  it("scores exact two-deck duplicates by the highest applicable category", () => {
    assert.deepStrictEqual(classifyCombination(cards(
      "copy-0:hearts:9",
      "copy-1:hearts:9",
      "copy-0:hearts:4",
    )), {
      category: "flush",
      score: 4,
    });
    assert.deepStrictEqual(classifyCombination(cards(
      "copy-0:clubs:10",
      "copy-1:clubs:10",
      "copy-0:diamonds:10",
    )), {
      category: "three_of_a_kind",
      score: 8,
    });
  });
});
