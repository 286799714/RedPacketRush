import assert from "assert";

import type { PhysicalCard } from "../src/match/cards.js";
import type { MatchView } from "../src/match/MatchEngine.js";
import {
  chooseAutomaticPlayCardIds,
  chooseBotCommand,
} from "../src/match/botPolicy.js";

function card(index: number): PhysicalCard {
  return {
    id: `card-${index}`,
    rank: (index + 2) as PhysicalCard["rank"],
    suit: "clubs",
    copyIndex: 0,
  };
}

function specifiedCard(
  id: string,
  rank: PhysicalCard["rank"],
  suit: PhysicalCard["suit"],
): PhysicalCard {
  return { id, rank, suit, copyIndex: 0 };
}

function matchView(overrides: {
  phase?: MatchView["publicState"]["phase"];
  seatIndex?: number;
  actorSeatIndex?: number;
  hand?: readonly PhysicalCard[];
  playedCards?: readonly PhysicalCard[];
  claimCommitted?: boolean;
  claimAwards?: MatchView["publicState"]["claimAwards"];
  pendingDiscardSeatIndexes?: readonly number[];
} = {}): MatchView {
  const seatIndex = overrides.seatIndex ?? 1;
  return {
    publicState: {
      phase: overrides.phase ?? "actor_play",
      actorSeatIndex: overrides.actorSeatIndex ?? seatIndex,
      firstActorSeatIndex: 0,
      drawPileCount: 20,
      playedCards: overrides.playedCards ?? [],
      playedCategory: null,
      playedScore: 0,
      turnNumber: 3,
      revealedClaims: [],
      claimAwards: overrides.claimAwards ?? [],
      discardedCards: [],
      sealedCardCount: 0,
      pendingDiscardSeatIndexes: overrides.pendingDiscardSeatIndexes ?? [],
      finalResults: [],
      winnerSeatIndexes: [],
      participants: [],
      events: [],
    },
    privateState: {
      seatIndex,
      participantId: `participant-${seatIndex}`,
      hand: overrides.hand ?? Array.from({ length: 5 }, (_, index) => card(index)),
      claimCommitted: overrides.claimCommitted ?? false,
      claimCardId: null,
      finalCommitted: false,
      finalGroups: [],
    },
  };
}

describe("bot policy", () => {
  it("plays the strongest three-card combination for either strategy", () => {
    const view = matchView({
      hand: [
        specifiedCard("pair-2-clubs", 2, "clubs"),
        specifiedCard("pair-2-hearts", 2, "hearts"),
        specifiedCard("straight-9", 9, "hearts"),
        specifiedCard("straight-10", 10, "spades"),
        specifiedCard("straight-j", 11, "diamonds"),
      ],
    });
    const expectedCommand = {
      type: "play_cards",
      cardIds: ["straight-j", "straight-10", "straight-9"],
    };

    assert.deepStrictEqual(chooseBotCommand(view, "conservative"), expectedCommand);
    assert.deepStrictEqual(chooseBotCommand(view, "aggressive"), expectedCommand);
  });

  it("always claims the strongest played card for the aggressive strategy", () => {
    const playedCards = [
      specifiedCard("middle", 10, "hearts"),
      specifiedCard("strongest", 14, "clubs"),
      specifiedCard("weakest", 3, "diamonds"),
    ];
    const view = matchView({
      phase: "claim_commit",
      actorSeatIndex: 0,
      playedCards,
    });

    assert.deepStrictEqual(chooseBotCommand(view, "aggressive"), {
      type: "claim",
      cardId: "strongest",
    });
  });

  it("passes when no played card improves a conservative hand", () => {
    const view = matchView({
      phase: "claim_commit",
      actorSeatIndex: 0,
      hand: [
        specifiedCard("heart-2", 2, "hearts"),
        specifiedCard("diamond-2", 2, "diamonds"),
        specifiedCard("heart-7", 7, "hearts"),
        specifiedCard("diamond-7", 7, "diamonds"),
        specifiedCard("spade-j", 11, "spades"),
      ],
      playedCards: [
        specifiedCard("club-4", 4, "clubs"),
        specifiedCard("club-5", 5, "clubs"),
        specifiedCard("club-9", 9, "clubs"),
      ],
    });

    assert.deepStrictEqual(chooseBotCommand(view, "conservative"), {
      type: "claim",
      cardId: null,
    });
  });

  it("prioritizes a rank improvement over suit and adjacency improvements", () => {
    const view = matchView({
      phase: "claim_commit",
      actorSeatIndex: 0,
      hand: [
        specifiedCard("heart-5", 5, "hearts"),
        specifiedCard("diamond-8", 8, "diamonds"),
        specifiedCard("spade-10", 10, "spades"),
        specifiedCard("heart-q", 12, "hearts"),
        specifiedCard("diamond-2", 2, "diamonds"),
      ],
      playedCards: [
        specifiedCard("rank-match", 5, "clubs"),
        specifiedCard("suit-match", 14, "hearts"),
        specifiedCard("adjacent-match", 13, "clubs"),
      ],
    });

    assert.deepStrictEqual(chooseBotCommand(view, "conservative"), {
      type: "claim",
      cardId: "rank-match",
    });
  });

  it("prioritizes a suit improvement over an adjacency improvement", () => {
    const view = matchView({
      phase: "claim_commit",
      actorSeatIndex: 0,
      hand: [
        specifiedCard("heart-2", 2, "hearts"),
        specifiedCard("heart-3", 3, "hearts"),
        specifiedCard("diamond-7", 7, "diamonds"),
        specifiedCard("diamond-8", 8, "diamonds"),
        specifiedCard("spade-q", 12, "spades"),
      ],
      playedCards: [
        specifiedCard("suit-match", 10, "hearts"),
        specifiedCard("adjacent-match", 13, "clubs"),
        specifiedCard("no-match", 5, "clubs"),
      ],
    });

    assert.deepStrictEqual(chooseBotCommand(view, "conservative"), {
      type: "claim",
      cardId: "suit-match",
    });
  });

  it("claims the strongest card when a conservative hand is above a pair", () => {
    const view = matchView({
      phase: "claim_commit",
      actorSeatIndex: 0,
      hand: [
        specifiedCard("straight-4", 4, "hearts"),
        specifiedCard("straight-5", 5, "diamonds"),
        specifiedCard("straight-6", 6, "spades"),
        specifiedCard("heart-9", 9, "hearts"),
        specifiedCard("diamond-j", 11, "diamonds"),
      ],
      playedCards: [
        specifiedCard("adjacent-7", 7, "clubs"),
        specifiedCard("strongest-a", 14, "clubs"),
        specifiedCard("adjacent-3", 3, "clubs"),
      ],
    });

    assert.deepStrictEqual(chooseBotCommand(view, "conservative"), {
      type: "claim",
      cardId: "strongest-a",
    });
  });

  it("does not act after its Claim is committed", () => {
    const playedCards = [card(0), card(1), card(2)];
    const view = matchView({
        phase: "claim_commit",
        actorSeatIndex: 0,
        playedCards,
        claimCommitted: true,
    });

    assert.strictEqual(chooseBotCommand(view, "conservative"), null);
    assert.strictEqual(chooseBotCommand(view, "aggressive"), null);
  });

  it("may discard the awarded card itself", () => {
    const hand = [
      specifiedCard("heart-5", 5, "hearts"),
      specifiedCard("diamond-6", 6, "diamonds"),
      specifiedCard("heart-9", 9, "hearts"),
      specifiedCard("heart-10", 10, "hearts"),
      specifiedCard("diamond-k", 13, "diamonds"),
      specifiedCard("awarded-isolated", 2, "clubs"),
    ];
    const view = matchView({
      phase: "award_discard",
      hand,
      pendingDiscardSeatIndexes: [1],
      claimAwards: [{ seatIndex: 1, card: hand[5], source: "unique" }],
    });

    for (const strategy of ["conservative", "aggressive"] as const) {
      assert.deepStrictEqual(chooseBotCommand(view, strategy), {
        type: "discard",
        cardId: "awarded-isolated",
        turnNumber: 3,
      });
    }
  });

  it("uses the same five-class discard priority for both strategies", () => {
    const scenarios: readonly {
      readonly name: string;
      readonly hand: readonly PhysicalCard[];
      readonly expectedCardId: string;
    }[] = [
      {
        name: "isolated before every relation",
        hand: [
          specifiedCard("isolated", 2, "clubs"),
          specifiedCard("heart-5", 5, "hearts"),
          specifiedCard("diamond-6", 6, "diamonds"),
          specifiedCard("heart-9", 9, "hearts"),
          specifiedCard("heart-10", 10, "hearts"),
          specifiedCard("diamond-k", 13, "diamonds"),
        ],
        expectedCardId: "isolated",
      },
      {
        name: "adjacency only before suit",
        hand: [
          specifiedCard("adjacent-low", 2, "clubs"),
          specifiedCard("adjacent-high", 3, "diamonds"),
          specifiedCard("heart-5", 5, "hearts"),
          specifiedCard("heart-9", 9, "hearts"),
          specifiedCard("spade-q", 12, "spades"),
          specifiedCard("spade-a", 14, "spades"),
        ],
        expectedCardId: "adjacent-low",
      },
      {
        name: "suit before suit and adjacency",
        hand: [
          specifiedCard("suit-low", 2, "hearts"),
          specifiedCard("suit-high", 5, "hearts"),
          specifiedCard("diamond-7", 7, "diamonds"),
          specifiedCard("diamond-8", 8, "diamonds"),
          specifiedCard("spade-10", 10, "spades"),
          specifiedCard("spade-j", 11, "spades"),
        ],
        expectedCardId: "suit-low",
      },
      {
        name: "suit and adjacency before same rank",
        hand: [
          specifiedCard("suited-adjacent-low", 2, "hearts"),
          specifiedCard("suited-adjacent-high", 3, "hearts"),
          specifiedCard("rank-7-diamond", 7, "diamonds"),
          specifiedCard("rank-7-spade", 7, "spades"),
          specifiedCard("rank-10-club", 10, "clubs"),
          specifiedCard("rank-10-heart", 10, "hearts"),
        ],
        expectedCardId: "suited-adjacent-low",
      },
      {
        name: "weakest same-rank card as fallback",
        hand: [
          specifiedCard("pair-2-club", 2, "clubs"),
          specifiedCard("pair-2-heart", 2, "hearts"),
          specifiedCard("pair-7-club", 7, "clubs"),
          specifiedCard("pair-7-diamond", 7, "diamonds"),
          specifiedCard("pair-10-spade", 10, "spades"),
          specifiedCard("pair-10-heart", 10, "hearts"),
        ],
        expectedCardId: "pair-2-club",
      },
    ];

    for (const scenario of scenarios) {
      const view = matchView({
        phase: "award_discard",
        hand: scenario.hand,
        pendingDiscardSeatIndexes: [1],
      });
      for (const strategy of ["conservative", "aggressive"] as const) {
        assert.deepStrictEqual(chooseBotCommand(view, strategy), {
          type: "discard",
          cardId: scenario.expectedCardId,
          turnNumber: 3,
        }, `${strategy}: ${scenario.name}`);
      }
    }
  });

  it("uses the first three cards for the deterministic actor deadline fallback", () => {
    assert.deepStrictEqual(chooseAutomaticPlayCardIds(matchView()), [
      "card-0",
      "card-1",
      "card-2",
    ]);
  });

  it("does nothing when the seat has no legal command in the current phase", () => {
    assert.strictEqual(chooseBotCommand(
      matchView({ phase: "claim_reveal" }),
      "conservative",
    ), null);
    assert.strictEqual(chooseBotCommand(
      matchView({ actorSeatIndex: 0 }),
      "aggressive",
    ), null);
  });
});
